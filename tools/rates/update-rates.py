#!/usr/bin/env python3
"""Publishes the day's exchange rates for NoBudget as rates.json in the nobudget-rates repo.

Runs daily on a machine at home. It only makes outbound connections (the rates source and a git push
to GitHub); the app downloads rates.json from GitHub, so nobody ever connects to this machine.
Usage: update-rates.py            fetch, check and publish
       update-rates.py --out F    fetch and check only, writing the file to F
"""
import datetime
import json
import math
import os
import pathlib
import subprocess
import sys
import urllib.request

# Public-domain (CC0) daily rates, with the project's own fallback mirror.
SOURCES = [
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json',
    'https://latest.currency-api.pages.dev/v1/currencies/usd.min.json',
]
REMOTE = 'git@github.com:raigon-pawa/nobudget-rates.git'
HOME = pathlib.Path(os.environ.get('NOBUDGET_RATES_HOME', pathlib.Path.home() / '.local/share/nobudget-rates'))
# Commits carry a fixed name, address and UTC time: git's defaults would publish this machine's user, hostname
# and time zone.
GIT_ENV = {
    'GIT_AUTHOR_NAME': 'NoBudget rates', 'GIT_AUTHOR_EMAIL': 'noreply@nobudget.raigonpawa.dev',
    'GIT_COMMITTER_NAME': 'NoBudget rates', 'GIT_COMMITTER_EMAIL': 'noreply@nobudget.raigonpawa.dev',
    'TZ': 'UTC',
    'GIT_SSH_COMMAND': f'ssh -i {HOME / "deploy_key"} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new',
}


def fetch():
    errors = []
    for url in SOURCES:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'nobudget-rates'})
            with urllib.request.urlopen(req, timeout=30) as r:
                return check(json.load(r))
        except Exception as e:  # try the next source
            errors.append(f'{url}: {e}')
    sys.exit('No usable rates:\n' + '\n'.join(errors))


def check(data):
    """Units per US dollar, upper-case codes. Refuses anything that looks wrong rather than publishing it."""
    date = datetime.date.fromisoformat(data['date'])
    rates = {k.upper(): v for k, v in data['usd'].items() if len(k) == 3 and k.isalpha()}
    rates = {k: v for k, v in rates.items() if isinstance(v, (int, float)) and math.isfinite(v) and v > 0}
    if rates.get('USD') != 1 or len(rates) < 100 or not 0.5 < rates.get('EUR', 0) < 2:
        raise ValueError('rates look wrong')
    if (datetime.date.today() - date).days > 7:
        raise ValueError(f'rates are from {date}')
    return {'date': date.isoformat(), 'source': 'github.com/fawazahmed0/exchange-api (CC0)', 'rates': rates}


def git(*args):
    subprocess.run(['git', *args], cwd=HOME / 'repo', env={**os.environ, **GIT_ENV}, check=True)


def main():
    out = fetch()
    text = json.dumps(out, indent=0, sort_keys=True) + '\n'
    if sys.argv[1:2] == ['--out']:
        pathlib.Path(sys.argv[2]).write_text(text)
        return
    repo = HOME / 'repo'
    if not repo.exists():
        subprocess.run(['git', 'clone', '-q', REMOTE, str(repo)], env={**os.environ, **GIT_ENV}, check=True)
    git('fetch', '-q', 'origin')
    git('reset', '-q', '--hard', 'origin/main')
    file = repo / 'rates.json'
    if file.exists() and json.loads(file.read_text())['date'] >= out['date']:
        print(f'Already published rates for {out["date"]}; the source has nothing newer yet.')
        return
    file.write_text(text)
    git('add', 'rates.json')
    git('commit', '-q', '-m', f'Rates for {out["date"]}')
    git('push', '-q', 'origin', 'HEAD:main')
    print(f'Published rates for {out["date"]}.')


if __name__ == '__main__':
    main()
