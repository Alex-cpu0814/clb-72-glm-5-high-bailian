#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "20cdbb714300bdb2502d9ac44740c85c64cce691" ]] || fail 'Unexpected Base commit'
git checkout 20cdbb714300bdb2502d9ac44740c85c64cce691 -- src/test/python/jpy_array_test.py || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/src/test/python/jpy_array_test.py b/src/test/python/jpy_array_test.py
index 85f159e..431011e 100644
--- a/src/test/python/jpy_array_test.py
+++ b/src/test/python/jpy_array_test.py
@@ -98,6 +98,16 @@ class TestJavaArrays(unittest.TestCase):
         self.do_test_array_protocol('java.lang.Object', [None, None, None], [File('A'), 'B', 3])
 
 
+    # see https://github.com/bcdev/jpy/issues/52
+    def test_array_item_del(self):
+        Integer = jpy.get_type('java.lang.Integer')
+        a = jpy.array(Integer, 3)
+        try:
+            del a[1]
+        except RuntimeError as err:
+            self.assertEqual(err.args[0], 'cannot delete items of Java arrays')
+
+
     def do_test_basic_buffer_protocol(self, type, itemsize, values):
 
         a = jpy.array(type, 4)
CLB_TEST_PATCH

mkdir -p /benchmark || fail 'Cannot create evaluation fixture directory'
cat > /benchmark/unittest_native_runner.py <<'EOF_10222fae15dd' || fail 'Cannot write /benchmark/unittest_native_runner.py'
"""Run complete original unittest methods and preserve actual native child results."""
from __future__ import print_function
import glob,imp,json,os,re,subprocess,sys,unittest
child_mode='--child' in sys.argv[1:];collect='--collect-only' in sys.argv[1:]
nodes=[x for x in sys.argv[1:]if x not in ['--child','--collect-only']]
if not nodes or len(nodes)!=len(set(nodes)):raise ValueError('Unique original unittest IDs required')
for node in nodes:
 if not re.match(r'^src/test/python/[A-Za-z0-9_]+\.py::[A-Za-z0-9_]+::test_[A-Za-z0-9_]+$',node):raise ValueError('Original jpy unittest node required')
if not child_mode:
 command=[sys.executable,os.path.abspath(__file__),'--child']+(['--collect-only']if collect else[])+nodes
 child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=1,universal_newlines=True)
 starts=[];terminals={}
 for line in child.stdout:
  sys.stdout.write(line);sys.stdout.flush()
  fields=line.rstrip('\n').rsplit(' ',1)
  if len(fields)==2 and fields[0]in nodes:
   if fields[1]=='STARTED':starts.append(fields[0])
   elif fields[1]in ['PASSED','FAILED','ERROR','SKIPPED']:terminals[fields[0]]=fields[1]
 code=child.wait();shell_code=code if code>=0 else 128-code
 for report in sorted(glob.glob('/testbed/hs_err_pid*.log')):
  print('__JVM_FATAL_REPORT_BEGIN__ '+report)
  with open(report)as f:sys.stdout.write(f.read())
  print('__JVM_FATAL_REPORT_END__ '+report)
 if not collect:print('__NATIVE_PROCESS_RESULT__ '+json.dumps({'command':command,'requested_nodes':nodes,'observed_starts':starts,'terminal_statuses':terminals,'returncode':code,'signal':{-11:'SIGSEGV',-6:'SIGABRT'}.get(code),'shell_exit_code':shell_code,'executed':True}))
 sys.exit(shell_code)

import ctypes,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
libc=ctypes.CDLL(None,use_errno=True)
if libc.prctl(4,0,0,0,0)!=0 or libc.prctl(3,0,0,0,0)!=0:raise RuntimeError('Could not set process core/dumpability metadata')
suite=unittest.TestSuite();mapping={};modules={}
for node in nodes:
 path,cls,method=node.split('::');source=os.path.realpath('/testbed/'+path)
 if not source.startswith('/testbed/src/test/python/')or not os.path.isfile(source):raise ValueError('Unexpected upstream test path')
 if path not in modules:
  sys.path.insert(0,os.path.dirname(source));modules[path]=imp.load_source(os.path.basename(path)[:-3],source)
 test=getattr(modules[path],cls)(method);mapping[test.id()]=node;suite.addTest(test)
if collect:
 for node in nodes:print(node)
 sys.exit(0)
class CanonicalResult(unittest.TextTestResult):
 def startTest(self,test):
  print(mapping[test.id()]+' STARTED');sys.stdout.flush();unittest.TextTestResult.startTest(self,test)
 def record(self,test,status):print(mapping[test.id()]+' '+status);sys.stdout.flush()
 def addSuccess(self,test):unittest.TextTestResult.addSuccess(self,test);self.record(test,'PASSED')
 def addFailure(self,test,err):unittest.TextTestResult.addFailure(self,test,err);self.record(test,'FAILED')
 def addError(self,test,err):unittest.TextTestResult.addError(self,test,err);self.record(test,'ERROR')
 def addSkip(self,test,reason):unittest.TextTestResult.addSkip(self,test,reason);self.record(test,'SKIPPED')
result=unittest.TextTestRunner(stream=sys.stdout,verbosity=2,resultclass=CanonicalResult).run(suite)
sys.exit(0 if result.wasSuccessful()else 1)
EOF_10222fae15dd
(python2.7 setup.py clean build_ext --inplace --force && mkdir -p target/test-classes && javac -d target/test-classes src/main/java/org/jpy/annotations/*.java src/test/java/org/jpy/fixtures/*.java) || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
python2.7 /benchmark/unittest_native_runner.py \
    src/test/python/jpy_array_test.py::TestJavaArrays::test_array_int \
    src/test/python/jpy_array_test.py::TestJavaArrays::test_array_object \
    src/test/python/jpy_array_test.py::TestJavaArrays::test_buffer_int \
    src/test/python/jpy_array_test.py::TestJavaArrays::test_array_item_del
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout 20cdbb714300bdb2502d9ac44740c85c64cce691 -- src/test/python/jpy_array_test.py || fail 'Test file restoration failed'
exit "$test_status"
