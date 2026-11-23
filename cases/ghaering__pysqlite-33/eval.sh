#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "d7c44a6b62ccf27ae2a006d32dc25cd49ca45320" ]] || fail 'Unexpected Base commit'
git checkout d7c44a6b62ccf27ae2a006d32dc25cd49ca45320 -- lib/test/hooks.py || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/lib/test/hooks.py b/lib/test/hooks.py
index e7cd49d..60adb5b 100644
--- a/lib/test/hooks.py
+++ b/lib/test/hooks.py
@@ -152,10 +152,31 @@ class ProgressTests(unittest.TestCase):
         con.execute("select 1 union select 2 union select 3").fetchall()
         self.assertEqual(action, 0, "progress handler was not cleared")
 
+class LimitTests(unittest.TestCase):
+    def CheckGetLimit(self):
+        """
+        Test that the get limit method return something useful.
+        """
+        con = sqlite.connect(":memory:")
+        val = con.get_limit(sqlite.SQLITE_LIMIT_VARIABLE_NUMBER)
+        self.assertTrue(val > 0)
+
+    def CheckSetLimit(self):
+        """
+        Test that the set limit method actally changes limits.
+        """
+        con = sqlite.connect(":memory:")
+        oldval = con.get_limit(sqlite.SQLITE_LIMIT_VARIABLE_NUMBER)
+        con.set_limit(sqlite.SQLITE_LIMIT_VARIABLE_NUMBER, oldval - 1)
+        newval = con.get_limit(sqlite.SQLITE_LIMIT_VARIABLE_NUMBER)
+
+        self.assertEqual(newval, oldval - 1)
+
 def suite():
     collation_suite = unittest.makeSuite(CollationTests, "Check")
     progress_suite = unittest.makeSuite(ProgressTests, "Check")
-    return unittest.TestSuite((collation_suite, progress_suite))
+    limit_suite = unittest.makeSuite(LimitTests, "Check")
+    return unittest.TestSuite((collation_suite, progress_suite, limit_suite))
 
 def test():
     runner = unittest.TextTestRunner()
CLB_TEST_PATCH

mkdir -p /benchmark || fail 'Cannot create evaluation fixture directory'
cat > /benchmark/pysqlite_unittest_nodes.py <<'EOF_ded51a817fc4' || fail 'Cannot write /benchmark/pysqlite_unittest_nodes.py'
"""Execute complete upstream unittest cases without rewriting their bodies (Python2 compatible)."""
from __future__ import print_function
import ctypes
import importlib
import resource
import sys
import unittest

resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(4, 0, 0, 0, 0) != 0 or libc.prctl(3, 0, 0, 0, 0) != 0:
    raise RuntimeError('Could not disable process dumpability')
collect = '--collect-only' in sys.argv[1:]
nodes = [n for n in sys.argv[1:] if n != '--collect-only']
if not nodes or len(nodes) != len(set(nodes)):
    raise ValueError('Unique original unittest node IDs required')
suite = unittest.TestSuite()
node_by_test = {}
for node in nodes:
    path, cls, method = node.split('::')
    if not path.startswith('lib/test/') or not path.endswith('.py') or not method.startswith('Check'):
        raise ValueError('Expected original pysqlite Check method')
    module = importlib.import_module('pysqlite2.test.' + path[len('lib/test/'):-3])
    if not module.__file__.startswith('/testbed/build/lib.linux-x86_64-2.7/pysqlite2/test/'):
        raise RuntimeError('Unexpected original module path')
    case = getattr(module, cls)(method)
    node_by_test[case.id()] = node
    suite.addTest(case)
if collect:
    for node in nodes:
        print(node)
    sys.exit(0)

class CanonicalResult(unittest.TextTestResult):
    def record(self, case, status):
        print(node_by_test[case.id()] + ' ' + status)
        sys.stdout.flush()
    def addSuccess(self, case):
        unittest.TextTestResult.addSuccess(self, case)
        self.record(case, 'PASSED')
    def addFailure(self, case, err):
        unittest.TextTestResult.addFailure(self, case, err)
        self.record(case, 'FAILED')
    def addError(self, case, err):
        unittest.TextTestResult.addError(self, case, err)
        self.record(case, 'ERROR')
    def addSkip(self, case, reason):
        unittest.TextTestResult.addSkip(self, case, reason)
        self.record(case, 'SKIPPED')

result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2, resultclass=CanonicalResult).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
EOF_ded51a817fc4
python2.7 setup.py build_ext --force build_py --force || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
python2.7 /benchmark/pysqlite_unittest_nodes.py \
    lib/test/hooks.py::CollationTests::CheckCreateCollationNotCallable \
    lib/test/hooks.py::ProgressTests::CheckProgressHandlerUsed \
    lib/test/hooks.py::ProgressTests::CheckCancelOperation \
    lib/test/hooks.py::LimitTests::CheckGetLimit \
    lib/test/hooks.py::LimitTests::CheckSetLimit
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout d7c44a6b62ccf27ae2a006d32dc25cd49ca45320 -- lib/test/hooks.py || fail 'Test file restoration failed'
exit "$test_status"
