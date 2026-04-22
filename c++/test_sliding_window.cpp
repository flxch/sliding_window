/**
 * test_sliding_window.cpp  –  unit tests for SlidingWindow.hpp
 *
 * Build:
 *   g++ -std=c++17 -Wall -Wextra -g -fsanitize=address \
 *       test_sliding_window.cpp -o test_sw_cpp
 *
 * Run:
 *   ./test_sw_cpp
 */

#include "SlidingWindow.hpp"

#include <cassert>
#include <cmath>
#include <functional>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

// ── tiny test framework ────────────────────────────────────────────────

static int g_passed = 0, g_failed = 0;

#define CHECK(cond, msg)                                                \
    do {                                                                \
        if (cond) {                                                     \
            std::cout << "  PASS  " << (msg) << "\n";                  \
            ++g_passed;                                                 \
        } else {                                                        \
            std::cout << "  FAIL  " << (msg)                           \
                      << "  (line " << __LINE__ << ")\n";              \
            ++g_failed;                                                 \
        }                                                               \
    } while (false)

// ── helpers ───────────────────────────────────────────────────────────

/**
 * Build a generator that yields elements from a vector one at a time.
 * Returns std::nullopt once the vector is exhausted.
 */
template <typename T>
std::function<std::optional<T>()> make_gen(const std::vector<T>& v)
{
    auto it = std::make_shared<typename std::vector<T>::const_iterator>(v.begin());
    auto end = v.end();
    return [it, end]() mutable -> std::optional<T> {
        if (*it == end) return std::nullopt;
        return *(*it)++;
    };
}

/**
 * Run the algorithm over `xs` for the given windows with operator `op`.
 * Returns a vector of results.
 */
template <typename T, typename Op>
std::vector<T> run(const std::vector<T>& xs,
                   const std::vector<sw::Window>& ws,
                   Op op)
{
    std::vector<T> results;
    auto sink = [&](const T& v) { results.push_back(v); };
    sw::SlidingWindow<T, Op> sw_inst(make_gen(xs), sink, op);
    for (auto& w : ws)
        sw_inst.slide(w);
    return results;
}

// Convenience overloads for common operators on int
auto add = [](int a, int b) { return a + b; };
auto mx  = [](int a, int b) { return std::max(a, b); };
auto mn  = [](int a, int b) { return std::min(a, b); };

// ── tests ─────────────────────────────────────────────────────────────

void test_single_window()
{
    std::cout << "\n[test_single_window]\n";
    auto r = run<int>({1,2,3,4,5}, {{0,4}}, add);
    CHECK(r.size() == 1,   "result count == 1");
    CHECK(r[0]     == 15,  "sum(0..4) == 15");
}

void test_fixed_size_window_sum()
{
    std::cout << "\n[test_fixed_size_window_sum]\n";
    auto r = run<int>({1,2,3,4,5}, {{0,2},{1,3},{2,4}}, add);
    CHECK(r.size() == 3,  "result count == 3");
    CHECK(r[0] ==  6,     "sum(0..2) == 6");
    CHECK(r[1] ==  9,     "sum(1..3) == 9");
    CHECK(r[2] == 12,     "sum(2..4) == 12");
}

void test_variable_size_window()
{
    std::cout << "\n[test_variable_size_window]\n";
    // Example from the paper
    std::vector<int> xs = {3,1,4,1,5,9,2,6};
    auto r = run<int>(xs, {{0,1},{0,3},{2,5},{3,7}}, add);
    CHECK(r.size() == 4,  "result count == 4");
    CHECK(r[0] ==  4,     "sum(0..1) == 4");
    CHECK(r[1] ==  9,     "sum(0..3) == 9");
    CHECK(r[2] == 19,     "sum(2..5) == 19");
    CHECK(r[3] == 23,     "sum(3..7) == 23");
}

void test_max_operator()
{
    std::cout << "\n[test_max_operator]\n";
    std::vector<int> xs = {3,1,4,1,5,9,2,6};
    auto r = run<int>(xs, {{0,2},{1,4},{3,7}}, mx);
    CHECK(r.size() == 3,  "result count == 3");
    CHECK(r[0] == 4,      "max(0..2) == 4");
    CHECK(r[1] == 5,      "max(1..4) == 5");
    CHECK(r[2] == 9,      "max(3..7) == 9");
}

void test_min_operator()
{
    std::cout << "\n[test_min_operator]\n";
    std::vector<int> xs = {5,3,8,1,4};
    auto r = run<int>(xs, {{0,1},{1,2},{2,4},{0,4}}, mn);
    CHECK(r.size() == 4,  "result count == 4");
    CHECK(r[0] == 3,      "min(0..1) == 3");
    CHECK(r[1] == 3,      "min(1..2) == 3");
    CHECK(r[2] == 1,      "min(2..4) == 1");
    CHECK(r[3] == 1,      "min(0..4) == 1");
}

void test_singleton_elements()
{
    std::cout << "\n[test_singleton_elements]\n";
    auto r = run<int>({7,3,9,2}, {{0,0},{1,1},{2,2},{3,3}}, add);
    CHECK(r.size() == 4,  "result count == 4");
    CHECK(r[0] == 7,      "xs[0] == 7");
    CHECK(r[1] == 3,      "xs[1] == 3");
    CHECK(r[2] == 9,      "xs[2] == 9");
    CHECK(r[3] == 2,      "xs[3] == 2");
}

void test_growing_window()
{
    std::cout << "\n[test_growing_window]\n";
    // Prefix sums: left always 0, right grows
    auto r = run<int>({1,2,3,4,5},
                      {{0,0},{0,1},{0,2},{0,3},{0,4}}, add);
    CHECK(r.size() == 5,   "result count == 5");
    CHECK(r[0] ==  1,      "prefix[0] == 1");
    CHECK(r[1] ==  3,      "prefix[1] == 3");
    CHECK(r[2] ==  6,      "prefix[2] == 6");
    CHECK(r[3] == 10,      "prefix[3] == 10");
    CHECK(r[4] == 15,      "prefix[4] == 15");
}

void test_shrinking_left()
{
    std::cout << "\n[test_shrinking_left]\n";
    // Suffix sums: right fixed at 4, left grows
    auto r = run<int>({1,2,3,4,5},
                      {{0,4},{1,4},{2,4},{3,4},{4,4}}, add);
    CHECK(r.size() == 5,   "result count == 5");
    CHECK(r[0] == 15,      "suffix[0] == 15");
    CHECK(r[1] == 14,      "suffix[1] == 14");
    CHECK(r[2] == 12,      "suffix[2] == 12");
    CHECK(r[3] ==  9,      "suffix[3] == 9");
    CHECK(r[4] ==  5,      "suffix[4] == 5");
}

void test_gap_between_windows()
{
    std::cout << "\n[test_gap_between_windows]\n";
    // Windows with a gap in the stream
    std::vector<int> xs = {0,1,2,3,4,5,6,7,8,9};
    auto r = run<int>(xs, {{0,1},{5,7},{8,9}}, add);
    CHECK(r.size() == 3,   "result count == 3");
    CHECK(r[0] ==  1,      "sum(0..1) == 1");
    CHECK(r[1] == 18,      "sum(5..7) == 18");
    CHECK(r[2] == 17,      "sum(8..9) == 17");
}

void test_no_windows()
{
    std::cout << "\n[test_no_windows]\n";
    auto r = run<int>({1,2,3}, {}, add);
    CHECK(r.empty(), "no windows → no results");
}

void test_large_stream_fixed_window()
{
    std::cout << "\n[test_large_stream_fixed_window]\n";
    const int N = 1000, W = 10;
    std::vector<int> xs(N);
    for (int i = 0; i < N; i++) xs[i] = i + 1;

    std::vector<sw::Window> ws;
    ws.reserve(N - W + 1);
    for (int i = 0; i <= N - W; i++)
        ws.push_back({i, i + W - 1});

    auto r = run<int>(xs, ws, add);
    CHECK((int)r.size() == N - W + 1, "result count == 991");

    bool ok = true;
    for (int i = 0; i <= N - W; i++) {
        int expected = W * i + W * (W + 1) / 2;
        if (r[i] != expected) { ok = false; break; }
    }
    CHECK(ok, "all sliding sums correct");
}

void test_overlapping_windows()
{
    std::cout << "\n[test_overlapping_windows]\n";
    // l non-decreasing AND r non-decreasing (algorithm precondition)
    std::vector<int> xs = {2,4,6,8,10};
    auto r = run<int>(xs, {{0,4},{1,4},{1,4},{2,4},{3,4}}, add);
    CHECK(r.size() == 5,   "result count == 5");
    CHECK(r[0] == 30,      "sum(0..4) == 30");
    CHECK(r[1] == 28,      "sum(1..4) == 28");
    CHECK(r[2] == 28,      "sum(1..4) == 28 (repeated)");
    CHECK(r[3] == 24,      "sum(2..4) == 24");
    CHECK(r[4] == 18,      "sum(3..4) == 18");
}

// ── string concatenation operator (non-numeric type test) ─────────────

void test_string_concatenation()
{
    std::cout << "\n[test_string_concatenation]\n";
    std::vector<std::string> xs = {"a","b","c","d","e"};
    auto cat = [](const std::string& a, const std::string& b) {
        return a + b;
    };
    auto r = run<std::string>(xs, {{0,2},{1,3},{2,4}}, cat);
    CHECK(r.size() == 3,    "result count == 3");
    CHECK(r[0] == "abc",    "cat(0..2) == \"abc\"");
    CHECK(r[1] == "bcd",    "cat(1..3) == \"bcd\"");
    CHECK(r[2] == "cde",    "cat(2..4) == \"cde\"");
}

// ── double floating-point sum ──────────────────────────────────────────

void test_double_sum()
{
    std::cout << "\n[test_double_sum]\n";
    // Windows must have non-decreasing l and r.
    // {0,2},{1,3},{2,4}: l=0,1,2 r=2,3,4 – both non-decreasing.
    std::vector<double> xs = {0.1, 0.2, 0.3, 0.4, 0.5};
    auto r = run<double>(xs, {{0,2},{1,3},{2,4}},
                         [](double a, double b) { return a + b; });
    // sum(0..2)=0.6, sum(1..3)=0.9, sum(2..4)=1.2
    CHECK(r.size() == 3,                 "result count == 3");
    CHECK(std::fabs(r[0] - 0.6) < 1e-9, "sum(0..2) ≈ 0.6");
    CHECK(std::fabs(r[1] - 0.9) < 1e-9, "sum(1..3) ≈ 0.9");
    CHECK(std::fabs(r[2] - 1.2) < 1e-9, "sum(2..4) ≈ 1.2");
}

// ── generator exhaustion mid-stream returns false ──────────────────────

void test_stream_exhaustion()
{
    std::cout << "\n[test_stream_exhaustion]\n";
    // xs only has 3 elements but the window asks for index 4
    std::vector<int> xs = {1,2,3};
    std::vector<int> results;
    auto sink = [&](const int& v) { results.push_back(v); };
    sw::SlidingWindow<int> sw_inst(make_gen(xs), sink,
                                   [](int a, int b){ return a+b; });
    bool ok1 = sw_inst.slide({0,2});  // consumes all 3 elements: sum=6
    bool ok2 = sw_inst.slide({1,4});  // needs index 3 and 4 – stream exhausted
    CHECK(ok1,              "first slide succeeds");
    CHECK(!ok2,             "second slide fails (stream exhausted)");
    CHECK(results.size()==1,"only one result emitted");
    CHECK(results[0] == 6,  "sum(0..2) == 6");
}

// ── factory function ───────────────────────────────────────────────────

void test_make_sliding_window()
{
    std::cout << "\n[test_make_sliding_window]\n";
    std::vector<int> xs = {10,20,30,40,50};
    std::vector<int> results;

    auto sw_inst = sw::make_sliding_window<int>(
        make_gen(xs),
        [&](const int& v) { results.push_back(v); },
        [](int a, int b) { return a + b; }
    );

    sw_inst.slide({0,1});
    sw_inst.slide({2,4});
    CHECK(results.size() == 2,   "result count == 2");
    CHECK(results[0] == 30,      "sum(0..1) == 30");
    CHECK(results[1] == 120,     "sum(2..4) == 120");
}

// ── correctness cross-check: C++ vs brute force ────────────────────────

void test_crosscheck_brute_force()
{
    std::cout << "\n[test_crosscheck_brute_force]\n";
    // Generate a varied set of valid (non-decreasing l and r) windows
    // over a medium-sized stream and compare against brute force sums.
    const int N = 200;
    std::vector<int> xs(N);
    for (int i = 0; i < N; i++) xs[i] = (i * 17 + 5) % 100;  // pseudo-random

    std::vector<sw::Window> ws;
    int l = 0, r = 0;
    for (int step = 0; step < 80 && r < N; step++) {
        // advance l by 0 or 1, r by 1 or 2
        l = std::min(l + (step % 3 == 0 ? 1 : 0), r);
        r = std::min(r + 1 + (step % 5 == 0 ? 1 : 0), N - 1);
        if (l > r) l = r;
        ws.push_back({l, r});
    }

    auto r_algo = run<int>(xs, ws, add);

    bool ok = (r_algo.size() == ws.size());
    for (size_t i = 0; i < ws.size() && ok; i++) {
        int brute = 0;
        for (int j = ws[i].left; j <= ws[i].right; j++)
            brute += xs[j];
        if (r_algo[i] != brute) ok = false;
    }
    CHECK(ok, "algorithm matches brute-force for all windows");
}

// ── main ───────────────────────────────────────────────────────────────

int main()
{
    std::cout << "=== Sliding Window (C++) – unit tests ===\n";

    test_single_window();
    test_fixed_size_window_sum();
    test_variable_size_window();
    test_max_operator();
    test_min_operator();
    test_singleton_elements();
    test_growing_window();
    test_shrinking_left();
    test_gap_between_windows();
    test_no_windows();
    test_large_stream_fixed_window();
    test_overlapping_windows();
    test_string_concatenation();
    test_double_sum();
    test_stream_exhaustion();
    test_make_sliding_window();
    test_crosscheck_brute_force();

    std::cout << "\n=== Results: " << g_passed << " passed, "
              << g_failed << " failed ===\n";
    return g_failed ? 1 : 0;
}
