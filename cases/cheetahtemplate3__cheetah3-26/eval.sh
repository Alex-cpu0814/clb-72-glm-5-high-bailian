#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "c86628cad04edc5167f9a9c8999abc62c6558e7b" ]] || fail 'Unexpected Base commit'
git checkout c86628cad04edc5167f9a9c8999abc62c6558e7b -- Cheetah/Tests/SyntaxAndOutput.py || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/Cheetah/Tests/SyntaxAndOutput.py b/Cheetah/Tests/SyntaxAndOutput.py
index c6fa39d..a2ee63c 100755
--- a/Cheetah/Tests/SyntaxAndOutput.py
+++ b/Cheetah/Tests/SyntaxAndOutput.py
@@ -3049,6 +3049,12 @@ class GetVar(OutputTest):               # Template.getVar()
         self.verify("$getVar('$bogus',  1234)",
                     "1234")
 
+    def test6(self):
+        """$getVar('$') raises ValueError
+        """
+        with self.assertRaises(ValueError):
+            self.verify("$getVar('$')", "never get here")
+
 
 class MiscComplexSyntax(OutputTest):
     def test1(self):
CLB_TEST_PATCH

python setup.py build_ext --inplace || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
python -m pytest -vv --color=no -o console_output_style=classic -c /dev/null --rootdir=/testbed -p no:cacheprovider \
    Cheetah/Tests/SyntaxAndOutput.py::GetVar::test1 \
    Cheetah/Tests/SyntaxAndOutput.py::GetVar::test2 \
    Cheetah/Tests/SyntaxAndOutput.py::GetVar::test6
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout c86628cad04edc5167f9a9c8999abc62c6558e7b -- Cheetah/Tests/SyntaxAndOutput.py || fail 'Test file restoration failed'
exit "$test_status"
