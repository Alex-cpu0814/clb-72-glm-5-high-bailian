#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "1df1513c64079a5100cdc2a372558e1f77849c0f" ]] || fail 'Unexpected Base commit'
git checkout 1df1513c64079a5100cdc2a372558e1f77849c0f -- junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java b/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
index 00be130..c173164 100644
--- a/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
+++ b/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
@@ -18,12 +18,15 @@
 package org.newsclub.net.unix;
 
 import static org.junit.jupiter.api.Assertions.assertFalse;
+import static org.junit.jupiter.api.Assertions.assertThrows;
 import static org.junit.jupiter.api.Assertions.assertTrue;
 
+import java.io.File;
 import java.io.IOException;
 import java.io.InputStream;
 import java.net.Socket;
 import java.net.SocketException;
+import java.net.SocketTimeoutException;
 import java.util.concurrent.Semaphore;
 import java.util.concurrent.TimeUnit;
 
@@ -100,4 +103,24 @@ public class SoTimeoutTest extends SocketTestBase {
       }
     }
   }
+
+  @Test
+  public void testSocketTimeoutException() throws Exception {
+    final File tempFile = newTempFile();
+    final AFUNIXSocketAddress address = AFUNIXSocketAddress.of(tempFile);
+    try (AFUNIXServerSocket server = AFUNIXServerSocket.bindOn(address);
+        AFUNIXSocket client = AFUNIXSocket.connectTo(address)) {
+
+      final AFUNIXSocket socket = server.accept();
+      socket.setSoTimeout(500);
+      byte[] buf = new byte[socket.getReceiveBufferSize()];
+      InputStream in = socket.getInputStream();
+
+      assertThrows(SocketTimeoutException.class, () -> {
+        in.read(buf);
+      });
+    } finally {
+      tempFile.delete();
+    }
+  }
 }
CLB_TEST_PATCH

mkdir -p /benchmark || fail 'Cannot create evaluation fixture directory'
cat > /benchmark/surefire_test_nodes.py <<'EOF_4c395be7a6ea' || fail 'Cannot write /benchmark/surefire_test_nodes.py'
#!/usr/bin/env python3
"""Emit Maven Surefire XML results in the evaluator's stable line format."""

import pathlib
import sys
import xml.etree.ElementTree as ET


def main():
    report_dir = pathlib.Path(sys.argv[1])
    found = 0
    for path in sorted(report_dir.glob("TEST-*.xml")):
        root = ET.parse(path).getroot()
        for case in root.iter("testcase"):
            class_name = case.get("classname", "unknown")
            method = case.get("name", "unknown")
            if case.find("failure") is not None:
                status = "FAILED"
            elif case.find("error") is not None:
                status = "ERROR"
            elif case.find("skipped") is not None:
                status = "SKIPPED"
            else:
                status = "PASSED"
            print(f"{class_name}.{method} {status}")
            found += 1
    if found == 0:
        print("No Surefire test results found", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
EOF_4c395be7a6ea
mvn -B -o -Prelease-native \
        -pl junixsocket-native-common,junixsocket-native-custom -am clean install \
        -Dmaven.test.skip=true \
        '-Djunixsocket.native.clang.c.options=-Wall -Wextra -Wno-reserved-id-macro -Wno-undef -Wno-cast-qual -Wno-disabled-macro-expansion -Wno-language-extension-token -Wno-gnu-auto-type -Wno-c++11-extensions -Wno-c++98-compat -Wno-empty-translation-unit -Wno-gnu-empty-initializer -Werror-implicit-function-declaration -Wint-conversion -Wno-unused-command-line-argument -fno-strict-overflow -finline-functions -fwrapv -fPIC -fvisibility=hidden -fno-common -Os -std=gnu11 -Djunixsocket_use_poll_for_read' \
        -Djunixsocket.custom.arch=amd64-Linux-clang-jni \
        -Djunixsocket.custom.shaded=default || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
(
    report_dir=/testbed/junixsocket-common/target/surefire-reports
    rm -rf "$report_dir" || exit 2
    mvn -B -o -Dstyle.color=never -f junixsocket-common/pom.xml test \
        '-Dtest=SoTimeoutTest#issue14Pass'
    control_status=$?
    python3 /benchmark/surefire_test_nodes.py "$report_dir" || exit 2
    if [[ "$control_status" -ne 0 ]]; then
        exit "$control_status"
    fi

    rm -rf "$report_dir" || exit 2
    timeout --signal=TERM --kill-after=5s 30s \
        mvn -B -o -Dstyle.color=never -f junixsocket-common/pom.xml test \
        '-Dtest=SoTimeoutTest#testSocketTimeoutException'
    target_status=$?
    if [[ "$target_status" -eq 124 || "$target_status" -eq 137 ]]; then
        printf '%s\n' 'org.newsclub.net.unix.SoTimeoutTest.testSocketTimeoutException ERROR'
        exit 1
    fi
    python3 /benchmark/surefire_test_nodes.py "$report_dir" || exit 2
    exit "$target_status"
)
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout 1df1513c64079a5100cdc2a372558e1f77849c0f -- junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java || fail 'Test file restoration failed'
exit "$test_status"
