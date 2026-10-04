"""Read-only billing lookup for one retained generation; never retry inference.

The established private loader alone consumes credentials. Original request,
response and receipt files remain immutable. No account-wide data is requested.
"""
from datetime import datetime, timezone
from decimal import Decimal
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

from frozen_run import digest, LOADER, PRIVATE_ROOT, write


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def main(response_path, destination):
    source, output = Path(response_path).resolve(), Path(destination).resolve()
    if output.exists():
        raise ValueError('already queried')
    generation = json.loads(source.read_text())['id']
    if not isinstance(generation, str) or not re.fullmatch(r'gen-[A-Za-z0-9-]{1,100}', generation):
        raise ValueError('invalid generation')
    sys.path.insert(0, str(LOADER.parent))
    from run_private_env import load_credentials
    load_credentials(PRIVATE_ROOT / 'evaluation-v2')
    key = os.environ['OPENROUTER_API_KEY']
    request = urllib.request.Request('https://openrouter.ai/api/v1/generation?' + urllib.parse.urlencode(dict(id=generation)),
                                     headers={'Authorization': 'Bearer ' + key})
    row = dict(generation_id=generation, source_response_sha256=digest(source),
               queried_at=datetime.now(timezone.utc).isoformat(), inference_requests=0)
    opener = urllib.request.build_opener(NoRedirects())
    try:
        with opener.open(request, timeout=30) as reply:
            raw = reply.read(200001)
            if len(raw) > 200000 or key in raw.decode('utf-8'):
                raise ValueError('invalid reply')
            data = json.loads(raw)['data']
            if data['id'] != generation:
                raise ValueError('different generation')
            cost = Decimal(str(data['total_cost']))
            if isinstance(data['total_cost'], bool) or not cost.is_finite() or cost < 0:
                raise ValueError('invalid cost')
            row.update(status='resolved', reported_total_cost_usd=str(cost),
                       model=data.get('model'), provider=data.get('provider_name'))
    except urllib.error.HTTPError as error:
        row.update(status='unresolved', http_status=error.code)
    write(output, row)
    print('Billing lookup: ' + row['status'])


if __name__ == '__main__':
    try:
        main(*sys.argv[1:])
    except Exception:
        raise SystemExit('Billing lookup stopped; no configuration or exception contents displayed.')
