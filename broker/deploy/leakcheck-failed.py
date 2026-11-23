"""Tell the owner's phones that the daily leak check failed or was stopped.

Run by credbroker-leakcheck-failed.service, which systemd starts when
credbroker-leakcheck.service ends as failed: a non-zero exit other than 3, its
time limit, its memory limit, or a kill. It is the backstop for every way the
check can be stopped before it sends its own alert.

Standard library only, and nothing from the broker's own code: it must still
work when whatever stopped the check is wrong with that code or its packages.
The text is fixed. It reads nothing the check wrote.
"""
import http.client
import json
import os
import socket
import sys

SOCKET = os.environ.get("CREDBROKER_VOUCH_SOCKET", "/run/vouch/broker.sock")
TITLE = "The daily leak check failed or was stopped"
BODY = ("The leak check's unit ended as failed. If the check was able to, it sent its own alert just before this "
        "one, saying why. If this is the only alert, the check was stopped from outside (out of memory, out of "
        "time, or killed) and today's check is not complete. See: journalctl -u credbroker-leakcheck\n"
        "Anything it had already found is in that log as 'possible leak' and was not sent to you.")


class Unix(http.client.HTTPConnection):
    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(20)
        self.sock.connect(SOCKET)


def main() -> None:
    conn = Unix("localhost")
    try:
        conn.request("POST", "/v1/alerts", headers={"Content-Type": "application/json"}, body=json.dumps(
            {"alert_id": "leakfail_" + os.urandom(9).hex(), "severity": "critical", "title": TITLE, "body": BODY}))
        status = conn.getresponse().status
    except (OSError, http.client.HTTPException) as e:
        sys.exit(f"could not alert the owner's phone through {SOCKET}: {type(e).__name__}")
    finally:
        conn.close()
    if status != 202:
        sys.exit(f"Vouch refused the alert: HTTP {status}")


if __name__ == "__main__":
    main()
