#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "ba3d20f60e7fbf1a49ae1f4bac09111299d104ee" ]] || fail 'Unexpected Base commit'
git checkout ba3d20f60e7fbf1a49ae1f4bac09111299d104ee -- junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java b/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
index c1731641..b1ff3691 100644
--- a/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
+++ b/junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java
@@ -24,6 +24,7 @@ import static org.junit.jupiter.api.Assertions.assertTrue;
 import java.io.File;
 import java.io.IOException;
 import java.io.InputStream;
+import java.io.OutputStream;
 import java.net.Socket;
 import java.net.SocketException;
 import java.net.SocketTimeoutException;
@@ -105,7 +106,7 @@ public class SoTimeoutTest extends SocketTestBase {
   }
 
   @Test
-  public void testSocketTimeoutException() throws Exception {
+  public void testSocketTimeoutExceptionRead() throws Exception {
     final File tempFile = newTempFile();
     final AFUNIXSocketAddress address = AFUNIXSocketAddress.of(tempFile);
     try (AFUNIXServerSocket server = AFUNIXServerSocket.bindOn(address);
@@ -123,4 +124,25 @@ public class SoTimeoutTest extends SocketTestBase {
       tempFile.delete();
     }
   }
+
+  @Test
+  public void testSocketTimeoutExceptionWrite() throws Exception {
+    final File tempFile = newTempFile();
+    final AFUNIXSocketAddress address = AFUNIXSocketAddress.of(tempFile);
+    try (AFUNIXServerSocket server = AFUNIXServerSocket.bindOn(address);
+        AFUNIXSocket client = AFUNIXSocket.connectTo(address)) {
+
+      final AFUNIXSocket socket = server.accept();
+      socket.setSoTimeout(500);
+      byte[] buf = new byte[socket.getSendBufferSize()];
+      OutputStream out = socket.getOutputStream();
+
+      assertThrows(SocketTimeoutException.class, () -> {
+        out.write(buf);
+        out.write(buf);
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
        -Djunixsocket.custom.arch=amd64-Linux-clang-jni \
        -Djunixsocket.custom.shaded=default || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
(
    report_dir=/testbed/junixsocket-common/target/surefire-reports
    rm -rf "$report_dir" || exit 2
    mvn -B -o -Dstyle.color=never -f junixsocket-common/pom.xml test \
        '-Dtest=SoTimeoutTest#testSocketTimeoutExceptionRead'
    control_status=$?
    python3 /benchmark/surefire_test_nodes.py "$report_dir" || exit 2
    if [[ "$control_status" -ne 0 ]]; then
        exit "$control_status"
    fi

    rm -rf "$report_dir" || exit 2
    timeout --signal=TERM --kill-after=5s 15s \
        mvn -B -o -Dstyle.color=never -f junixsocket-common/pom.xml test \
        '-Dtest=SoTimeoutTest#testSocketTimeoutExceptionWrite'
    target_status=$?
    if [[ "$target_status" -eq 124 || "$target_status" -eq 137 ]]; then
        printf '%s\n' 'org.newsclub.net.unix.SoTimeoutTest.testSocketTimeoutExceptionWrite ERROR'
        exit 1
    fi
    python3 /benchmark/surefire_test_nodes.py "$report_dir" || exit 2
    exit "$target_status"
)
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout ba3d20f60e7fbf1a49ae1f4bac09111299d104ee -- junixsocket-common/src/test/java/org/newsclub/net/unix/SoTimeoutTest.java || fail 'Test file restoration failed'
exit "$test_status"
