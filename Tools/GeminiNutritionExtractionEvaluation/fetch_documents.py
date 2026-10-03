"""Bounded, unauthenticated fetch of frozen development source URLs only."""
import argparse
import hashlib
import http.client
from html.parser import HTMLParser
from urllib.parse import urlsplit, urljoin
from datetime import datetime, timezone
from pathlib import Path
from collect import private_write
from evaluate import verify

MAX_BYTES=2_000_000
MAX_TEXT=80_000

class VisibleText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip=[]; self.current=[]; self.lines=[]
    def flush(self):
        line=' '.join(''.join(self.current).split()).strip(' |')
        if line: self.lines.append(line)
        self.current=[]
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style','noscript','template','head'): self.skip.append(tag)
        if not self.skip and tag in ('p','div','tr','li','h1','h2','h3','h4','section','br'): self.flush()
    def handle_endtag(self,tag):
        if self.skip:
            if tag==self.skip[-1]: self.skip.pop()
            return
        if tag in ('td','th'): self.current.append(' | ')
        elif tag in ('p','div','tr','li','h1','h2','h3','h4','section'): self.flush()
    def handle_data(self,data):
        if not self.skip: self.current.append(data)
    def result(self):
        self.flush()
        text='\n'.join(f'L{i}: {line}' for i,line in enumerate(self.lines,1))
        if not text or len(text)>MAX_TEXT: raise ValueError('empty_or_oversize_document')
        return text

def read_url(url,allowed_host):
    current=url
    for _ in range(3):
        parsed=urlsplit(current)
        if parsed.scheme!='https' or parsed.hostname!=allowed_host or parsed.username or parsed.password or parsed.port not in (None,443):
            raise ValueError('redirect_outside_selected_host')
        conn=http.client.HTTPSConnection(parsed.hostname,timeout=20)
        try:
            conn.request('GET',parsed.path+('?' + parsed.query if parsed.query else ''),headers={'User-Agent':'WeeklyHealthReport-Local-Evaluation/1.0','Accept':'text/html'})
            reply=conn.getresponse()
            if reply.status in (301,302,303,307,308):
                current=urljoin(current,reply.getheader('Location','')); continue
            if reply.status!=200: raise ValueError('http_'+str(reply.status))
            if 'text/html' not in reply.getheader('Content-Type',''): raise ValueError('unsupported_content_type')
            raw=reply.read(MAX_BYTES+1)
            if len(raw)>MAX_BYTES: raise ValueError('oversize_html')
            parser=VisibleText();parser.feed(raw.decode('utf-8',errors='replace'))
            return dict(selected_url=url,retrieved_url=current,html_sha256=hashlib.sha256(raw).hexdigest(),text=parser.result())
        finally: conn.close()
    raise ValueError('redirect_limit')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output-dir',type=Path,required=True);a=ap.parse_args()
    corpus,contract=verify();a.output_dir.mkdir(mode=0o700,exist_ok=False)
    development={c['source'] for c in corpus['cases'] if c['split']=='development'}
    manifest=dict(fetched_at=datetime.now(timezone.utc).isoformat(),extractor_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),sources={})
    for name,source in corpus['sources'].items():
        if name not in development or not source['url']: continue
        try:
            doc=read_url(source['url'],urlsplit(source['url']).hostname)
            doc['text_sha256']=hashlib.sha256(doc['text'].encode()).hexdigest()
            private_write(a.output_dir/(name+'.json'),doc)
            manifest['sources'][name]={k:v for k,v in doc.items() if k!='text'}
            manifest['sources'][name]['outcome']='fetched'
        except Exception as error:
            safe=str(error)
            manifest['sources'][name]=dict(selected_url=source['url'],outcome=safe if safe.startswith('http_') or safe in {'redirect_outside_selected_host','unsupported_content_type','oversize_html','empty_or_oversize_document','redirect_limit'} else 'transport_error')
        private_write(a.output_dir/'manifest.json',manifest)
        print(name,manifest['sources'][name]['outcome'],flush=True)
