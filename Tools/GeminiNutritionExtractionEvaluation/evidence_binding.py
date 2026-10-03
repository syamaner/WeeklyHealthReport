"""Pure versioned binding of selected evidence to a provider request/result."""
from dataclasses import dataclass
import hashlib
import json


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()

@dataclass(frozen=True)
class Evidence:
    source_id: str
    source_url: str | None
    content: str
    content_sha256: str

    @classmethod
    def selected(cls, source_id, source_url, content):
        if not source_id or not content: raise ValueError('empty evidence')
        return cls(source_id,source_url,content,sha(content))

@dataclass(frozen=True)
class RequestEnvelope:
    evidence: Evidence
    request_json: str
    request_sha256: str

    @classmethod
    def create(cls,evidence,body):
        if sha(evidence.content)!=evidence.content_sha256: raise ValueError('evidence changed')
        payload=json.loads(body['input'])
        if payload.get('source_document',payload.get('evidence_panel'))!=evidence.content:
            raise ValueError('request evidence mismatch')
        if payload['selected_url']!=evidence.source_url or payload.get('selected_source_id')!=evidence.source_id or payload.get('evidence_sha256')!=evidence.content_sha256: raise ValueError('request source mismatch')
        encoded=json.dumps(body,sort_keys=True,ensure_ascii=False,allow_nan=False)
        return cls(evidence,encoded,sha(encoded))

    def body(self):
        if sha(self.request_json)!=self.request_sha256 or sha(self.evidence.content)!=self.evidence.content_sha256:
            raise ValueError('request changed')
        body=json.loads(self.request_json)
        check=type(self).create(self.evidence,body)
        if check!=self: raise ValueError('request binding mismatch')
        return body

    def bind(self,model_extraction):
        self.body()
        if type(model_extraction)is not dict or 'source_url' in model_extraction or 'provenance' in model_extraction:
            raise ValueError('model cannot write source identity')
        # Copy, never mutate the retained model result. Validation happens at the adapter boundary.
        result=json.loads(json.dumps(model_extraction,allow_nan=False))
        result['source_url']=self.evidence.source_url
        return dict(version='selected-evidence-envelope-v3',
                    provenance=dict(source_id=self.evidence.source_id,source_url=self.evidence.source_url,
                                    content_sha256=self.evidence.content_sha256,request_sha256=self.request_sha256),
                    extraction=result)


def resolve_record(lead,records):
    """Exact admitted-record resolution; never trust or silently repair model claims."""
    matches=[r for r in records if r['family']==lead['family'] and r['id']==lead['id']]
    if len(matches)!=1:return dict(status='unresolved',reason='missing_or_ambiguous_record',record=None)
    record=matches[0]
    if lead['name'] not in [record['name'], *record.get('reviewed_name_aliases',[])] or lead['preparation']!=record['preparation']:
        return dict(status='rejected_identity',reason='name_or_preparation_conflict',record=None)
    conflicts=[k for k,v in lead['claims'].items() if record['nutrients'].get(k)!=v]
    return dict(status='verified' if not conflicts else 'conflicting_claims',
                reason='exact_admitted_record' if not conflicts else 'claimed_values_not_supported',
                conflicts=conflicts,record=record,requires_user_confirmation=True)
