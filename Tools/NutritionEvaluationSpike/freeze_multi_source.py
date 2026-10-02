"""Build exposed synthetic references from pinned public catalogues, never observations.
Run explicitly when creating a NEW reviewed reference version; not part of evaluation.
"""
from decimal import Decimal
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent
VERSION=3
RES=HERE.parents[1]/'Packages/FoodLedgerKit/Sources/FoodGenericSearch/Resources'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def create():
    cofid=json.loads((RES/'cofid-2021-generic-search-v1.json').read_text())['records']
    usda=json.loads((RES/'usda-generic-v1.json').read_text())['records']
    records={r['record_id']:r for r in cofid}|{r['id']:r for r in usda}
    milk=next(r['record_id'] for r in cofid if r['worksheet_row']==1681)
    apple=next(r['record_id'] for r in cofid if r['worksheet_row']==30)
    uht=next(r['record_id'] for r in cofid if r['worksheet_row']==1684)
    ribeye=next(r['id'] for r in usda if r['fdcID']==2646172)
    umilk=next(r['id'] for r in usda if r['fdcID']==172217)
    # case, backend, entry, original, selected record, explicit action, amount, unit,
    # conversion offered/applied, resulting amount/unit (None means quantity blocked).
    specs=[
      ('usda-ribeye-100','usda','query','100g raw ribeye',ribeye,'accept',100,'g',False,False,100,'g'),
      ('usda-ribeye-50','usda','query','50g raw ribeye',ribeye,'accept',50,'g',False,False,50,'g'),
      ('usda-list-ribeye','usda','list','100g raw ribeye',ribeye,'accept',100,'g',False,False,100,'g'),
      ('composite-ribeye','composite','query','100g raw ribeye',ribeye,'accept',100,'g',False,False,100,'g'),
      ('composite-list-apple','composite','list','100g raw apples',apple,'accept',100,'g',False,False,100,'g'),
      ('milk-cofid-convert','cofid','query','200ml Milk whole pasteurised average',milk,'convert',200,'mL',True,True,206,'g'),
      ('milk-composite-convert','composite','query','200ml Milk whole pasteurised average',milk,'convert',200,'mL',True,True,206,'g'),
      ('milk-litres-convert','cofid','query','0.2l Milk whole pasteurised average',milk,'convert',200,'mL',True,True,206,'g'),
      ('milk-no-conversion-tap','cofid','query','200ml Milk whole pasteurised average',milk,'accept',200,'mL',True,False,200,'mL'),
      ('milk-edited-conversion','cofid','query','200ml Milk whole pasteurised average',milk,'convert_then_edit',200,'mL',True,False,100,'mL'),
      ('milk-uht-no-offer','cofid','query','200ml Milk whole UHT',uht,'convert',200,'mL',False,False,200,'mL'),
      ('milk-usda-no-offer','usda','query','200ml Milk whole',umilk,'convert',200,'mL',False,False,200,'mL'),
      ('milk-usda-unreviewed-amount','usda','query','200ml Milk whole without added',umilk,'convert',None,'g',False,False,None,None),
      ('usda-count-block','usda','list','2 ribeye',ribeye,'accept',2,'count',False,False,None,None),
    ]
    order=[t['key'] for t in json.loads((HERE/'linked-reference-v3.json').read_text())['cases'][0]['expected']['totals']]
    units={k:v['canonical_unit'] for k,v in cofid[0]['nutrients'].items()}
    cases=[];inputs=[]
    for cid,backend,entry,text,record,action,amount,unit,offered,applied,result,result_unit in specs:
        saved=result is not None
        totals=[]
        for key in order:
            known=None
            if saved and result_unit=='g':
                nutrient=records[record]['nutrients'].get(key,{})
                if record.startswith('cofid:'):
                    if nutrient.get('state')=='numeric' and nutrient.get('source_unit')==units[key]:known=Decimal(nutrient['value'])*Decimal(str(result))/100
                elif nutrient.get('unit')==units[key]:known=Decimal(str(nutrient['amount']))*Decimal(str(result))/100
            totals.append({'key':key,'known':float(known) if known is not None else None,'incomplete':int(saved and known is None),'estimate':known is not None})
        expected={'parser_route':'not_applicable' if entry=='list' else 'search','backend':backend,'entry':entry,'target_found':True,'selected_record':record,'handoff_value':amount,'handoff_unit':unit,
          'initially_undecided':True,'preaccept_blocked':True,'generic_estimate':True,'conversion_offered':offered,
          'conversion_applied':applied,'reopen_preserved':saved,'validation':'saved' if saved else 'blocked','error':'' if saved else ('invalidQuantity' if amount is None else 'missingConversion'),
          'edible_value':result,'edible_unit':result_unit,'saved_versions':int(saved),'operations':int(saved),'rows':int(saved),
          'original_preserved':saved,'provenance_preserved':saved,'totals':totals}
        cases.append({'case_id':cid,'kind':'save' if saved else 'block','expected':expected})
        inputs.append({'case_id':cid,'text':text,'backend':backend,'entry':entry,'target_record':record,'action':action})
    reference={'schema':'synthetic-multi-source-reference-v1','reference_quality':'public_catalogue_derived_exposed_synthetic',
      'source_sha256':{n:sha(RES/n) for n in ['cofid-2021-generic-search-v1.json','usda-generic-v1.json','cofid-whole-milk-volume-v1.json']},'cases':cases}
    for name,data in [(f'multi-input-v{VERSION}.json',{'schema':'synthetic-multi-source-input-v1','cases':inputs}),(f'multi-reference-v{VERSION}.json',reference)]:
        path=HERE/name
        if path.exists():raise ValueError('never_overwrite_frozen_reference')
        path.write_text(json.dumps(data,indent=2)+'\n')
    (HERE/f'multi-freeze-v{VERSION}.json').write_text(json.dumps({'schema':'synthetic-multi-source-freeze-v1','input_sha256':sha(HERE/f'multi-input-v{VERSION}.json'),'reference_sha256':sha(HERE/f'multi-reference-v{VERSION}.json')},indent=2)+'\n')
if __name__=='__main__':create()
