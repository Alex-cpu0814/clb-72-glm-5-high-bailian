#!/bin/bash
set -uo pipefail
ulimit -c 0

fail() {
    printf '%s\n' '>>>>> Tests Errored' "$1" >&2
    exit 2
}

cd /testbed || fail 'Cannot enter /testbed'
[[ "$(git rev-parse HEAD)" == "76b6f57a27f31cdefc23444f91611a00c9b4332d" ]] || fail 'Unexpected Base commit'
git checkout 76b6f57a27f31cdefc23444f91611a00c9b4332d -- fast_histogram/tests/test_histogram.py || fail 'Test file restoration failed'
git apply --whitespace=nowarn - <<'CLB_TEST_PATCH' || fail 'Test patch application failed'
diff --git a/fast_histogram/tests/test_histogram.py b/fast_histogram/tests/test_histogram.py
index 2215f02..0771e6a 100644
--- a/fast_histogram/tests/test_histogram.py
+++ b/fast_histogram/tests/test_histogram.py
@@ -85,3 +85,21 @@ def test_2d_compare_with_numpy(size, nx, xmin, xmax, ny, ymin, ymax, weights):
                        range=((xmin, xmax), (ymin, ymax)))
 
     np.testing.assert_equal(fast, reference)
+
+
+def test_nd_arrays():
+
+    x = np.random.random(1000)
+
+    result_1d = histogram1d(x, bins=10, range=(0, 1))
+    result_3d = histogram1d(x.reshape((10, 10, 10)), bins=10, range=(0, 1))
+
+    np.testing.assert_equal(result_1d, result_3d)
+
+    y = np.random.random(1000)
+
+    result_1d = histogram2d(x, y, bins=(10, 10), range=[(0, 1), (0, 1)])
+    result_3d = histogram2d(x.reshape((10, 10, 10)), y.reshape((10, 10, 10)),
+                            bins=(10, 10), range=[(0, 1), (0, 1)])
+
+    np.testing.assert_equal(result_1d, result_3d)
CLB_TEST_PATCH

python setup.py build_ext --inplace --force || fail 'Project build failed'
set +x
printf '%s\n' '>>>>> Start Test Output'
python -m pytest -vv --color=no -o console_output_style=classic -p no:warnings --hypothesis-show-statistics \
    fast_histogram/tests/test_histogram.py::test_1d_compare_with_numpy \
    fast_histogram/tests/test_histogram.py::test_2d_compare_with_numpy \
    fast_histogram/tests/test_histogram.py::test_nd_arrays
test_status=$?
# SWE-bench records the status of the command immediately before the end marker.
(exit "$test_status")
printf '%s\n' '>>>>> End Test Output'
git checkout 76b6f57a27f31cdefc23444f91611a00c9b4332d -- fast_histogram/tests/test_histogram.py || fail 'Test file restoration failed'
exit "$test_status"
