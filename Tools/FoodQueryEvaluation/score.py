"""Exact field and route metrics. Synthetic development evidence, never independent acceptance."""
import hashlib,json,math,sys
from collections import Counter
from pathlib import Path
LABELS=('search','clarify','reject')
def ratio(n,d):return n/d if d else None
def normal_attributes(values):
 out={}
 for k,v in values.items():
  if k.endswith('_percent'):
   try:
    n=float(v)
    if not math.isfinite(n):raise ValueError('Nonfinite attribute')
    out[k]=n
   except (TypeError,ValueError):out[k]=str(v)
  else:out[k]=str(v)
 return out
def evaluate(fixture,actual):
 cases=fixture['cases']
 if not cases:raise ValueError('Empty fixture')
 if len(actual)!=len(cases):raise ValueError('Missing or extra predictions')
 ids=[x['id'] for x in actual];byid={x['id']:x['parsed'] for x in actual}
 if len(set(ids))!=len(ids) or set(ids)!={c['id'] for c in cases}:raise ValueError('Duplicate or mismatched prediction IDs')
 if len({c['id'] for c in cases})!=len(cases):raise ValueError('Duplicate fixture IDs')
 matrix={e:{p:0 for p in LABELS} for e in LABELS}
 counts=Counter();search_counts=Counter();search_total=0;failures=[];families={};groups={}
 attr_tp=attr_fp=attr_fn=0;quantity_tp=quantity_fp=quantity_fn=0
 quantity_support=quantity_correct=value_errors=unit_errors=0;absolute=[];relative=[];unsafe=[];unit_matrix={}
 for c in cases:
  p=byid[c['id']];e=c['expected'];mismatches=[]
  if p.get('original')!=c['query']:raise ValueError('Original query lost')
  if p.get('route') not in LABELS or e['route'] not in LABELS:raise ValueError('Unknown route')
  matrix[e['route']][p['route']]+=1
  ea=normal_attributes(e['attributes']);pa=normal_attributes(p.get('attributes',{}))
  ep=set(ea.items());pp=set(pa.items());attr_tp+=len(ep&pp);attr_fp+=len(pp-ep);attr_fn+=len(ep-pp)
  eq=e['quantity'];pq=p.get('quantity')
  if pq is not None:
   if pq.get('unit') not in {'g','ml','count'} or not isinstance(pq.get('value'),(int,float)) or isinstance(pq['value'],bool) or not math.isfinite(pq['value']) or pq['value']<=0:
    raise ValueError('Malformed predicted quantity')
  quantity_tp+=eq is not None and pq is not None
  quantity_fp+=eq is None and pq is not None
  quantity_fn+=eq is not None and pq is None
  if eq:
   quantity_support+=1;quantity_correct+=eq==pq
   if pq:
    unit_matrix.setdefault(eq['unit'],Counter())[pq['unit']]+=1
    unit_errors+=pq['unit']!=eq['unit']
    if pq['unit']==eq['unit']:
     error=abs(pq['value']-eq['value']);absolute.append(error);relative.append(error/eq['value']);value_errors+=error>1e-9
  if e['route']!='search' and pq is not None:unsafe.append(c['id'])
  for field in ['food','attributes','quantity','route']:
   expected=ea if field=='attributes' else e[field];got=pa if field=='attributes' else p.get(field)
   if expected==got:counts[field]+=1
   else:mismatches.append(field)
  if e['route']=='search':
   search_total+=1
   for field in ['food','attributes','quantity','route']:
    if field not in mismatches:search_counts[field]+=1
   if not mismatches:search_counts['exact']+=1
  if not mismatches:counts['exact']+=1
  else:failures.append({'id':c['id'],'family':c['family'],'fields':mismatches})
  for target,key in [(families,c['family']),(groups,c.get('scenario_group',c['id']))]:
   f=target.setdefault(key,{'cases':0,'exact':0,'route_correct':0,'quantity_correct':0})
   f['cases']+=1;f['exact']+=not mismatches;f['route_correct']+=p['route']==e['route'];f['quantity_correct']+=eq==pq
 per_class={}
 for label in LABELS:
  tp=matrix[label][label];support=sum(matrix[label].values());predicted=sum(matrix[e][label] for e in LABELS)
  precision=ratio(tp,predicted);recall=ratio(tp,support)
  f1=ratio(2*tp,support+predicted)
  per_class[label]={'support':support,'predicted':predicted,'precision':precision,'recall':recall,'f1':f1}
 supported=[v for v in per_class.values() if v['support']]
 eligible=sum(matrix[e]['search'] for e in ['clarify','reject']);nonsearch=sum(sum(matrix[e].values()) for e in ['clarify','reject'])
 return {'metric_schema_version':2,'cases':len(cases),'correct_fields':dict(counts),'field_accuracy':{k:ratio(counts[k],len(cases)) for k in ['food','attributes','quantity','route','exact']},
 'search_cases':search_total,'search_correct_fields':dict(search_counts),
 'route_metrics':{'labels':LABELS,'orientation':'rows=expected; columns=predicted','confusion_matrix':matrix,'per_class':per_class,'accuracy':ratio(counts['route'],len(cases)),'macro_f1_supported_classes':sum(v['f1'] or 0 for v in supported)/len(supported) if supported else None,'balanced_accuracy':sum(v['recall'] for v in supported)/len(supported) if supported else None,'weighted_f1':sum((v['f1'] or 0)*v['support'] for v in supported)/len(cases)},
 'attribute_metrics':{'true_positive_pairs':attr_tp,'false_positive_pairs':attr_fp,'false_negative_pairs':attr_fn,'micro_precision':ratio(attr_tp,attr_tp+attr_fp),'micro_recall':ratio(attr_tp,attr_tp+attr_fn),'micro_f1':ratio(2*attr_tp,2*attr_tp+attr_fp+attr_fn)},
 'quantity_metrics':{'expected_present':quantity_support,'presence_precision':ratio(quantity_tp,quantity_tp+quantity_fp),'presence_recall':ratio(quantity_tp,quantity_tp+quantity_fn),'presence_f1':ratio(2*quantity_tp,2*quantity_tp+quantity_fp+quantity_fn),'present_exact_accuracy':ratio(quantity_correct,quantity_support),'missing':quantity_fn,'unexpected':quantity_fp,'unit_confusion_matrix':{k:dict(v) for k,v in unit_matrix.items()},'unit_errors':unit_errors,'value_errors_comparable_units':value_errors,'comparable_pairs':len(absolute),'mean_absolute_relative_error_comparable_pairs':sum(relative)/len(relative) if relative else None,'max_absolute_relative_error_comparable_pairs':max(relative) if relative else None},
 'safety_metrics':{'nonsearch_cases':nonsearch,'false_search_eligible':eligible,'false_search_eligible_rate':ratio(eligible,nonsearch),'unexpected_prefill_ids':unsafe,'unexpected_prefill_count':len(unsafe),'unexpected_prefill_rate':ratio(len(unsafe),nonsearch),'original_query_preservation':1.0},
 'families':families,'scenario_group_metrics':{'groups':len(groups),'macro_exact':sum(v['exact']/v['cases'] for v in groups.values())/len(groups),'macro_route_accuracy':sum(v['route_correct']/v['cases'] for v in groups.values())/len(groups)},'failures':failures,'independent_acceptance':False,
 'notes':['Same-author synthetic development cases; correlated variants, not population estimates.','Food/attributes on clarify/reject are tentative; strict field scores retain those disagreements.','Reason strings not scored. Undefined denominators are null.','Magnitude errors compare identical units only; no mean mixing grams, ml and counts.','Scenario groups fall back to case IDs where historical grouping is unavailable.']}
def main():
 fixture_path,actual_path,report_path=map(Path,sys.argv[1:4]);fixture=json.loads(fixture_path.read_text());actual=json.loads(actual_path.read_text())
 report=evaluate(fixture,actual);report['fixture_sha256']=hashlib.sha256(fixture_path.read_bytes()).hexdigest();report['predictions_sha256']=hashlib.sha256(actual_path.read_bytes()).hexdigest()
 report_path.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'cases':report['cases'],'correct_fields':report['correct_fields'],'unsafe_prefills':report['safety_metrics']['unexpected_prefill_count']}))
 if '--gate' in sys.argv[4:] and (report['correct_fields'].get('route',0)!=report['cases'] or report['correct_fields'].get('quantity',0)!=report['cases'] or report['search_correct_fields'].get('exact',0)!=report['search_cases']):raise SystemExit('Food query development regression failed; inspect the report')
if __name__=='__main__':main()
