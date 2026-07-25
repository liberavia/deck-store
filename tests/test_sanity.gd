extends GutTest

func test_sanity_check():
	assert_eq(1, 1, "Basic math should work")
	assert_true(true, "True should be true")

func test_math_operations():
	assert_eq(2 + 2, 4, "Addition should work")
	assert_eq(5 * 5, 25, "Multiplication should work")
