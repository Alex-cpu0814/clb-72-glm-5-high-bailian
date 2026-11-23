#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "4f7667c4655712fc7371c0dbab0de5bf785e5d3d" ]] || fail 'Unexpected Base commit'
rm -f -- benchmark-tests/src/test/java/org/newsclub/net/unix/FileDescriptorCastRegressionTest.java benchmark-tests/src/test/java/org/newsclub/net/unix/StdinSocketApp.java || fail 'Cannot remove added test files'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/benchmark-tests/src/test/java/org/newsclub/net/unix/FileDescriptorCastRegressionTest.java b/benchmark-tests/src/test/java/org/newsclub/net/unix/FileDescriptorCastRegressionTest.java
new file mode 100644
index 000000000..a941a14b8
--- /dev/null
+++ b/benchmark-tests/src/test/java/org/newsclub/net/unix/FileDescriptorCastRegressionTest.java
@@ -0,0 +1,99 @@
+/*
+ * Focused regression harness for junixsocket issue #97.
+ *
+ * The test body follows the official upstream test introduced by commit
+ * 2f8f096b84fba1a, with only the forked-process helper adapted for the
+ * pre-refactor parent tree.
+ */
+package org.newsclub.net.unix;
+
+import java.io.BufferedReader;
+import java.io.FileDescriptor;
+import java.io.InputStreamReader;
+import java.lang.ProcessBuilder.Redirect;
+import java.nio.charset.StandardCharsets;
+import java.nio.file.Paths;
+import java.util.concurrent.TimeUnit;
+
+public final class FileDescriptorCastRegressionTest {
+  private static final String CLASS_NAME = FileDescriptorCastRegressionTest.class.getName();
+
+  private FileDescriptorCastRegressionTest() {
+    throw new IllegalStateException("No instances");
+  }
+
+  private static void testForkedVMRedirectStdin() throws Exception {
+    AFUNIXSocketAddress addr = AFUNIXSocketAddress.ofNewTempFile();
+    try (AFUNIXServerSocket serverSocket = AFUNIXServerSocket.bindOn(addr);
+        AFUNIXSocket clientConn = AFUNIXSocket.connectTo(addr);
+        AFUNIXSocket serverConn = serverSocket.accept()) {
+      if (!addr.getFile().delete()) {
+        throw new AssertionError("Could not unlink temporary socket path");
+      }
+
+      String javaCommand = Paths.get(System.getProperty("java.home"), "bin", "java").toString();
+      ProcessBuilder processBuilder = new ProcessBuilder(javaCommand, "-cp",
+          System.getProperty("java.class.path"), StdinSocketApp.class.getName());
+      processBuilder.redirectInput(FileDescriptorCast.using(clientConn.getFileDescriptor()).as(
+          Redirect.class));
+      processBuilder.redirectError(Redirect.INHERIT);
+      Process process = processBuilder.start();
+      try {
+        try (BufferedReader reader = new BufferedReader(new InputStreamReader(serverConn
+            .getInputStream(), StandardCharsets.UTF_8))) {
+          String firstLine = reader.readLine();
+          if (!"Hello world".equals(firstLine)) {
+            throw new AssertionError("Unexpected output: " + firstLine);
+          }
+          String extraLine = reader.readLine();
+          if (extraLine != null) {
+            throw new AssertionError("Unexpected extra output: " + extraLine);
+          }
+        }
+        if (!process.waitFor(30, TimeUnit.SECONDS)) {
+          throw new AssertionError("Forked VM did not terminate");
+        }
+        if (process.exitValue() != 0) {
+          throw new AssertionError("Forked VM exited with " + process.exitValue());
+        }
+      } finally {
+        process.destroyForcibly();
+      }
+    }
+  }
+
+  private static void testStdoutFileDescriptorCast() throws Exception {
+    FileDescriptor descriptor = FileDescriptorCast.using(FileDescriptor.out)
+        .as(FileDescriptor.class);
+    if (descriptor != FileDescriptor.out || !descriptor.valid()) {
+      throw new AssertionError("stdout file descriptor cast was not preserved");
+    }
+  }
+
+  private static boolean run(String methodName, CheckedRunnable test) {
+    try {
+      test.run();
+      System.out.println(methodName + " (" + CLASS_NAME + ") ... ok");
+      return true;
+    } catch (Throwable throwable) {
+      throwable.printStackTrace(System.out);
+      System.out.println(methodName + " (" + CLASS_NAME + ") ... ERROR");
+      return false;
+    }
+  }
+
+  public static void main(String[] args) {
+    boolean targetPassed = run("testForkedVMRedirectStdin",
+        FileDescriptorCastRegressionTest::testForkedVMRedirectStdin);
+    boolean controlPassed = run("testStdoutFileDescriptorCast",
+        FileDescriptorCastRegressionTest::testStdoutFileDescriptorCast);
+    if (!targetPassed || !controlPassed) {
+      System.exit(1);
+    }
+  }
+
+  @FunctionalInterface
+  private interface CheckedRunnable {
+    void run() throws Exception;
+  }
+}
diff --git a/benchmark-tests/src/test/java/org/newsclub/net/unix/StdinSocketApp.java b/benchmark-tests/src/test/java/org/newsclub/net/unix/StdinSocketApp.java
new file mode 100644
index 000000000..74b7cd189
--- /dev/null
+++ b/benchmark-tests/src/test/java/org/newsclub/net/unix/StdinSocketApp.java
@@ -0,0 +1,36 @@
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
+package org.newsclub.net.unix;
+
+import java.io.FileDescriptor;
+import java.io.PrintStream;
+import java.nio.charset.StandardCharsets;
+
+/** A forked-VM helper used by the file-descriptor redirect regression test. */
+public final class StdinSocketApp {
+  private StdinSocketApp() {
+    throw new IllegalStateException("No instances");
+  }
+
+  public static void main(String[] args) throws Exception {
+    try (PrintStream out = new PrintStream(FileDescriptorCast.using(FileDescriptor.in)
+        .as(AFUNIXSocket.class).getOutputStream(), true, StandardCharsets.UTF_8.name())) {
+      out.println("Hello world");
+    }
+  }
+}
CLB_TEST_PATCH

mkdir -p /benchmark || fail 'Cannot create evaluation fixture directory'
cat > /benchmark/format_test_log.py <<'EOF_8a58ff4098c6' || fail 'Cannot write /benchmark/format_test_log.py'
"""Convert test results to the SWE-bench status-first log format."""

import io
import re
import sys

TEST_LINE = re.compile(
    r"^(?P<method>\S+) \((?P<class>[^)]+)\) \.\.\. "
    r"(?P<status>ok|FAIL|ERROR|skipped(?: .*)?)$"
)

TEST_START_LINE = re.compile(r"^(?P<method>\S+) \((?P<class>[^)]+)\) \.\.\. .*")

def normalize_status(raw_status):
    if raw_status == "ok":
        return "PASSED"
    if raw_status == "FAIL":
        return "FAILED"
    if raw_status == "ERROR":
        return "ERROR"
    if raw_status.startswith("skipped"):
        return "SKIPPED"
    return "UNKNOWN"

def parse_test_log(text):
    statuses = {}
    pending = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        match = TEST_LINE.match(line)
        if not match:
            if pending and (line in ("ok", "FAIL", "ERROR") or line.startswith("skipped")):
                statuses[pending] = normalize_status(line)
                pending = None
                continue
            start = TEST_START_LINE.match(line)
            if start:
                pending = "{}.{}".format(start.group("class"), start.group("method"))
            continue
        test_id = "{}.{}".format(match.group("class"), match.group("method"))
        statuses[test_id] = normalize_status(match.group("status"))
    return statuses


if __name__ == '__main__':
    with io.open(sys.argv[1], encoding='utf-8', errors='replace') as log:
        statuses = parse_test_log(log.read())
    for test_id, status in sorted(statuses.items()):
        # The upstream parser represents missing results by omitting the node.
        if status in ('PASSED', 'FAILED', 'ERROR', 'SKIPPED'):
            print(u'{} {}'.format(status, test_id))
EOF_8a58ff4098c6
(
    mvn -B -o -Prelease-native \
        -pl junixsocket-native-common,junixsocket-native-custom -am clean install \
        -Dmaven.test.skip=true \
        -Djunixsocket.custom.arch=amd64-Linux-clang-jni \
        -Djunixsocket.custom.shaded=default \
        && mvn -B -o -f junixsocket-common/pom.xml package -Dmaven.test.skip=true
) || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
(
    common_jar="$(find junixsocket-common/target -maxdepth 1 -type f \
        -name 'junixsocket-common-*.jar' ! -name '*-sources.jar' \
        ! -name '*-javadoc.jar' ! -name '*-tests.jar' | head -n 1)"
    native_common_jar="$(find junixsocket-native-common/target -maxdepth 1 -type f \
        -name 'junixsocket-native-common-*.jar' ! -name '*-sources.jar' \
        ! -name '*-javadoc.jar' | head -n 1)"
    native_custom_jar="$(find junixsocket-native-custom/target -maxdepth 1 -type f \
        -name '*default.jar' | head -n 1)"
    [[ -n "$common_jar" && -n "$native_common_jar" && -n "$native_custom_jar" ]] || exit 2
    class_path="$common_jar:$native_common_jar:$native_custom_jar"

    rm -rf benchmark-tests/target || exit 2
    mkdir -p benchmark-tests/target/classes || exit 2
    javac -cp "$class_path" -d benchmark-tests/target/classes \
        benchmark-tests/src/test/java/org/newsclub/net/unix/{FileDescriptorCastRegressionTest,StdinSocketApp}.java \
        || exit $?

    raw_log=$(mktemp) || exit 2
    trap 'rm -f "$raw_log"' EXIT
    java -cp "$class_path:benchmark-tests/target/classes" \
        org.newsclub.net.unix.FileDescriptorCastRegressionTest 2>&1 | tee "$raw_log"
    java_status=$?
    python3 /benchmark/format_test_log.py "$raw_log" || exit 2
    exit "$java_status"
)
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
rm -f -- benchmark-tests/src/test/java/org/newsclub/net/unix/FileDescriptorCastRegressionTest.java benchmark-tests/src/test/java/org/newsclub/net/unix/StdinSocketApp.java || fail 'Cannot remove added test files'
exit "$test_status"
