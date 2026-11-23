#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "7578a2470871e12dd72716925f60d857ad7eb409" ]] || fail 'Unexpected Base commit'
git checkout 7578a2470871e12dd72716925f60d857ad7eb409 -- junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java || fail 'Test file restoration failed'
rm -f -- junixsocket-common/src/test/java/org/newsclub/net/unix/domain/AbstractNamespaceTest.java || fail 'Cannot remove added test files'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java b/junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java
index d17b2013..828125a7 100644
--- a/junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java
+++ b/junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java
@@ -19,6 +19,7 @@ package org.newsclub.net.unix;
 
 import static org.junit.jupiter.api.Assertions.assertEquals;
 import static org.junit.jupiter.api.Assertions.assertFalse;
+import static org.junit.jupiter.api.Assertions.assertNotNull;
 import static org.junit.jupiter.api.Assertions.assertTrue;
 
 import java.io.File;
@@ -126,4 +127,10 @@ public class AFUNIXSocketAddressTest {
       assertTrue(socatString.contains(":"));
     }
   }
+
+  @Test
+  public void testAbstractNamespace() throws Exception {
+    assertNotNull(AFUNIXSocketAddress.inAbstractNamespace("test"));
+    assertNotNull(AFUNIXSocketAddress.inAbstractNamespace("test", 1234));
+  }
 }
diff --git a/junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java b/junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java
index 1d9cad11..0c841222 100644
--- a/junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java
+++ b/junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java
@@ -42,6 +42,8 @@ public class SelftestProvider {
 
     registerTest("junixsocket-common", org.newsclub.net.unix.AFUNIXSocketAddressTest.class);
 
+    registerTest(org.newsclub.net.unix.domain.AbstractNamespaceTest.class);
+
     registerTest(org.newsclub.net.unix.domain.AcceptTimeoutTest.class);
 
     // AncillaryMesageTest: currently only in junixsocket-tipc
diff --git a/junixsocket-common/src/test/java/org/newsclub/net/unix/domain/AbstractNamespaceTest.java b/junixsocket-common/src/test/java/org/newsclub/net/unix/domain/AbstractNamespaceTest.java
new file mode 100644
index 00000000..d754a62d
--- /dev/null
+++ b/junixsocket-common/src/test/java/org/newsclub/net/unix/domain/AbstractNamespaceTest.java
@@ -0,0 +1,85 @@
+/*
+ * junixsocket
+ *
+ * Copyright 2009-2022 Christian Kohlschütter
+ *
+ * Licensed under the Apache License, Version 2.0 (the "License");
+ * you may not use this file except in compliance with the License.
+ * You may obtain a copy of the License at
+ *
+ *     http://www.apache.org/licenses/LICENSE-2.0
+ *
+ * Unless required by applicable law or agreed to in writing, software
+ * distributed under the License is distributed on an "AS IS" BASIS,
+ * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
+ * See the License for the specific language governing permissions and
+ * limitations under the License.
+ */
+package org.newsclub.net.unix.domain;
+
+import static org.junit.jupiter.api.Assertions.assertEquals;
+
+import java.io.IOException;
+import java.util.UUID;
+import java.util.concurrent.CompletableFuture;
+
+import org.junit.jupiter.api.Test;
+import org.newsclub.net.unix.AFSocketCapability;
+import org.newsclub.net.unix.AFSocketCapabilityRequirement;
+import org.newsclub.net.unix.AFUNIXServerSocket;
+import org.newsclub.net.unix.AFUNIXSocket;
+import org.newsclub.net.unix.AFUNIXSocketAddress;
+import org.newsclub.net.unix.SocketTestBase;
+
+import com.kohlschutter.annotations.compiletime.SuppressFBWarnings;
+
+@AFSocketCapabilityRequirement({
+    AFSocketCapability.CAPABILITY_UNIX_DOMAIN, AFSocketCapability.CAPABILITY_ABSTRACT_NAMESPACE})
+@SuppressFBWarnings({
+    "THROWS_METHOD_THROWS_CLAUSE_THROWABLE", "THROWS_METHOD_THROWS_CLAUSE_BASIC_EXCEPTION",
+    "NM_SAME_SIMPLE_NAME_AS_SUPERCLASS"})
+public class AbstractNamespaceTest extends SocketTestBase<AFUNIXSocketAddress> {
+
+  public AbstractNamespaceTest() {
+    super(AFUNIXAddressSpecifics.INSTANCE);
+  }
+
+  private void testBind(AFUNIXSocketAddress addr) throws Exception {
+    testBind(addr, addr);
+  }
+
+  private void testBind(AFUNIXSocketAddress addr, AFUNIXSocketAddress expected) throws Exception {
+    try (AFUNIXServerSocket serverSocket = (AFUNIXServerSocket) newServerSocket()) {
+      serverSocket.bind(addr);
+
+      CompletableFuture<AFUNIXSocketAddress> cf = CompletableFuture.supplyAsync(() -> {
+        AFUNIXSocket socket;
+        try {
+          socket = AFUNIXSocket.connectTo(addr);
+        } catch (IOException e) {
+          throw new IllegalStateException(e);
+        }
+        return socket.getRemoteSocketAddress();
+      });
+      AFUNIXSocket accept = serverSocket.accept();
+      assertEquals(accept.getLocalSocketAddress(), cf.get());
+      assertEquals(expected, cf.get());
+    }
+  }
+
+  @Test
+  public void testBind() throws Exception {
+    testBind(AFUNIXSocketAddress.inAbstractNamespace("juxtest-" + UUID.randomUUID()));
+  }
+
+  @Test
+  public void testBindTrailingZeroes() throws Exception {
+    // trailing zeroes should be treated like other bytes
+    testBind(AFUNIXSocketAddress.of(new byte[] {0, 10, 0}));
+    testBind(AFUNIXSocketAddress.of(new byte[] {0, 10, 0, 0}));
+    testBind(AFUNIXSocketAddress.of(new byte[] {0, 'J', 0, 'U'}));
+
+    // any sequence of 0's -> null
+    testBind(AFUNIXSocketAddress.of(new byte[] {0, 0, 0}), null);
+  }
+}
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
mvn -B -o -Puse-snapshots,release-native \
        -pl junixsocket-native-custom -am clean install \
        -DskipTests \
        -Djunixsocket.custom.arch=amd64-Linux-clang-jni \
        -Djunixsocket.custom.shaded=default || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
(
    rm -rf /testbed/junixsocket-common/target/surefire-reports || exit 2
    mvn -B -o -Dstyle.color=never -Puse-snapshots -pl junixsocket-common -am test \
        '-Dtest=AbstractNamespaceTest,AFUNIXSocketAddressTest#testAbstractNamespace' \
        -Dsurefire.failIfNoSpecifiedTests=false
    maven_status=$?
    python3 /benchmark/surefire_test_nodes.py /testbed/junixsocket-common/target/surefire-reports || exit 2
    exit "$maven_status"
)
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout 7578a2470871e12dd72716925f60d857ad7eb409 -- junixsocket-common/src/test/java/org/newsclub/net/unix/AFUNIXSocketAddressTest.java junixsocket-common/src/test/java/org/newsclub/net/unix/SelftestProvider.java || fail 'Test file restoration failed'
rm -f -- junixsocket-common/src/test/java/org/newsclub/net/unix/domain/AbstractNamespaceTest.java || fail 'Cannot remove added test files'
exit "$test_status"
