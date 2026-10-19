"""Produce a complete SQL seed for a fresh constrained schema, before triggers.

No connection or database mutation occurs here. Values are fictional. Credentials
come from the environment. Generated columns are deliberately omitted from INSERT.
Run the future tagged build/SQL acceptance tests to establish actual loadability.
"""
from pathlib import Path
from decimal import Decimal
from datetime import datetime
import argparse
import json
import os
import re

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from argon2 import PasswordHasher


def materialize(output):
    root = Path(__file__).resolve().parents[1]
    model = json.loads((root / 'model.json').read_text())
    fixture = json.loads((root / 'sample-records.json').read_text())
    entities = {e['name']: e for e in model['entities']}
    key = bytes.fromhex(os.environ['FIXTURE_KEY_HEX'])
    password = os.environ['FIXTURE_PASSWORD']
    if len(key) != 32 or len(password) < 12:
        raise ValueError('Require a 32-byte fixture key and password of at least 12 characters')
    aes = AESGCM(key)
    hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4)
    key_id = b'fixture1'
    lines = [
        '-- Fictional seed; select an EMPTY application schema created from TDD 1.2.',
        '-- Load after tables/constraints and BEFORE lifecycle/immutability triggers.',
        '-- Never disable foreign keys. The build runner must stop on any SQL error.',
        '-- Use the same injected key/password in the isolated demo service.',
        "SET time_zone = '+00:00';",
        'START TRANSACTION;',
    ]
    counts = {}
    encrypted = hashed = 0
    for name in fixture['seed_order']:
        entity = entities[name]
        columns = [c for c in entity['columns'] if not c['nullable'].startswith('Generated')]
        pk = entity['pk'].strip('()').replace(' ', '').split(',')
        for row in fixture[name]:
            primary_key = '/'.join(str(row[k]) for k in pk)
            if name == 'User':
                primary_key = row['PublicAlias']
            elif name == 'RequestEvaluation':
                primary_key = f"{row['RequestID']}/{row['EvaluationKind']}/{row['ContextID']}"
            literals = []
            for column in columns:
                value = row[column['name']]
                kind = column['type']
                if isinstance(value, dict) and set(value) == {'encrypt'}:
                    aad = json.dumps([name, primary_key, column['name']], separators=(',', ':')).encode()
                    nonce = os.urandom(12)
                    plaintext = value['encrypt'].encode()
                    ciphertext = aes.encrypt(nonce, plaintext, aad)
                    # Check the field-bound fixture format; not an application security test.
                    assert aes.decrypt(nonce, ciphertext, aad) == plaintext
                    value = b'ML1' + bytes([len(key_id)]) + key_id + nonce + ciphertext
                    maximum = int(re.search(r'\((\d+)\)', kind).group(1))
                    if len(value) > maximum:
                        raise ValueError('Envelope exceeds declared column length')
                    encrypted += 1
                elif isinstance(value, dict) and value == {'hash_password_env': 'FIXTURE_PASSWORD'}:
                    value = hasher.hash(password)
                    assert hasher.verify(value, password)
                    hashed += 1
                if value is None:
                    literal = 'NULL'
                elif isinstance(value, bytes):
                    literal = "X'" + value.hex() + "'"
                elif kind == 'BINARY(16)':
                    if not re.fullmatch(r'[0-9a-f]{32}', value):
                        raise ValueError('Invalid binary UUID fixture')
                    literal = "X'" + value + "'"
                elif kind.startswith(('BIGINT', 'INT', 'SMALLINT', 'TINYINT')):
                    if not isinstance(value, int) or value < 0:
                        raise ValueError('Invalid unsigned integer fixture')
                    literal = str(value)
                elif kind.startswith('DECIMAL'):
                    amount = Decimal(value)
                    if not amount.is_finite() or amount != amount.quantize(Decimal('.01')):
                        raise ValueError('Invalid cents fixture')
                    literal = format(amount, '.2f')
                elif kind.startswith('DATETIME'):
                    value = datetime.fromisoformat(value.replace('Z', '+00:00')).strftime('%Y-%m-%d %H:%M:%S.%f')
                    literal = "'" + value + "'"
                elif kind == 'DATE':
                    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
                        raise ValueError('Invalid date fixture')
                    literal = "'" + value + "'"
                else:
                    # UTF-8 hex literals avoid SQL escaping/mode ambiguities, including receipts.
                    literal = "X'" + str(value).encode('utf-8').hex() + "'"
                literals.append(literal)
            identifiers = ', '.join('`' + c['name'] + '`' for c in columns)
            lines.append(f'INSERT INTO `{name}` ({identifiers}) VALUES ({", ".join(literals)});')
        counts[name] = len(fixture[name])
    lines.append('COMMIT;')
    lines.append('-- Expected row counts: ' + json.dumps(counts, sort_keys=True))
    # Never overwrite an existing seed or output credentials to the console.
    with Path(output).open('x', encoding='utf-8') as handle:
        handle.write('\n'.join(lines) + '\n')
    print(f'Wrote {sum(counts.values())} INSERTs; {encrypted} authenticated envelopes; {hashed} password hashes.')
    print('SQL NOT executed; schema, trigger, role and acceptance consistency remains unverified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        materialize(args.output)
    except (KeyError, ValueError) as error:
        # Do not display environment values or plaintext contents in failure messages.
        raise SystemExit('Fixture materialization failed: check input types, key/password configuration and column sizes.') from None
