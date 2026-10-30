"""Password verification and bounded, thread-safe single-instance sessions."""
import base64
import hashlib
import hmac
import secrets
import threading
import time


def hash_password(password):
    if not isinstance(password, str) or len(password) < 12 or len(password) > 256:
        raise ValueError('Password must contain 12 to 256 characters')
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
    return 'scrypt$16384$8$1$' + base64.b64encode(salt).decode() + '$' + base64.b64encode(digest).decode()


def verify_password(password, encoded):
    try:
        method, n, r, p, salt, expected = encoded.split('$')
        if method != 'scrypt' or (n, r, p) != ('16384', '8', '1') or not 0 < len(password) <= 256:
            return False
        digest = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt, validate=True), n=16384, r=8, p=1)
        return hmac.compare_digest(digest, base64.b64decode(expected, validate=True))
    except (ValueError, TypeError, AttributeError):
        return False


class Sessions:
    def __init__(self, clock=time.monotonic, idle=1800, absolute=28800):
        self.clock, self.idle, self.absolute = clock, idle, absolute
        self.lock, self.rows = threading.Lock(), {}

    @staticmethod
    def key(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def create(self, user):
        token, csrf, now = secrets.token_urlsafe(32), secrets.token_urlsafe(32), self.clock()
        with self.lock:
            self.rows = {k:v for k,v in self.rows.items() if now-v['seen'] < self.idle and now-v['created'] < self.absolute}
            if len(self.rows) >= 1000:
                raise ValueError('Session capacity reached')
            self.rows[self.key(token)] = {'user':user, 'csrf':csrf, 'created':now, 'seen':now}
        return token, csrf

    def get(self, token):
        now = self.clock()
        with self.lock:
            row = self.rows.get(self.key(token))
            if not row:
                return None
            if now-row['seen'] >= self.idle or now-row['created'] >= self.absolute:
                self.rows.pop(self.key(token), None)
                return None
            row['seen'] = now
            return dict(row)

    def revoke(self, token):
        with self.lock:
            self.rows.pop(self.key(token), None)
