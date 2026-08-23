// test_hirschberg.cpp — Compare standard O(n*m) LCS vs Hirschberg O(n) space.
//
// The standard char_diff uses O(n*m) time AND O(n*m) space (a 2D DP table).
// For large files, this can exhaust memory.
//
// Hirschberg's algorithm computes the SAME LCS in O(n*m) time but only
// O(n) space, by using divide-and-conquer: split the problem in half,
// find the optimal split point, and recurse.
//
// This test file compares:
// 1. Standard LCS (2D DP table) — current implementation
// 2. Hirschberg LCS (1D DP + divide-and-conquer) — proposed
//
// It verifies both produce identical LCS, and benchmarks speed/memory.
//
// Build: c++ -O2 -std=c++17 -o test_hirschberg test_hirschberg.cpp
// Run:   ./test_hirschberg

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <string>
#include <algorithm>
#include <chrono>
#include <sys/resource.h>

using namespace std;
using Clock = chrono::high_resolution_clock;

// --- Standard LCS (2D DP table, O(n*m) space) ---
struct CharOp { int type; int code; }; // 0=keep, 1=delete, 2=insert

vector<CharOp> standard_lcs(const vector<int>& a, const vector<int>& b) {
    int na = a.size(), nb = b.size();
    // DP table
    vector<vector<int>> dp(na + 1, vector<int>(nb + 1, 0));
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++)
            dp[i][j] = (a[i-1] == b[j-1]) ? dp[i-1][j-1] + 1
                       : max(dp[i-1][j], dp[i][j-1]);
    // Backtrack
    vector<CharOp> ops;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && a[i-1] == b[j-1]) {
            ops.push_back({0, a[i-1]}); i--; j--;
        } else if (j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j])) {
            ops.push_back({2, b[j-1]}); j--;
        } else {
            ops.push_back({1, a[i-1]}); i--;
        }
    }
    reverse(ops.begin(), ops.end());
    return ops;
}

// --- Hirschberg LCS (O(n) space, divide-and-conquer) ---

// Forward DP: compute last row of LCS lengths for a[0..na-1] vs b[0..nb-1]
// Returns a vector of size nb+1 with the LCS lengths.
vector<int> lcs_forward_row(const vector<int>& a, const vector<int>& b) {
    int nb = b.size();
    vector<int> prev(nb + 1, 0), curr(nb + 1, 0);
    for (size_t i = 0; i < a.size(); i++) {
        for (int j = 1; j <= nb; j++) {
            curr[j] = (a[i] == b[j-1]) ? prev[j-1] + 1
                     : max(prev[j], curr[j-1]);
        }
        swap(prev, curr);
        fill(curr.begin(), curr.end(), 0);
    }
    return prev;
}

// Reverse DP: compute last row of LCS lengths for reversed a vs reversed b
vector<int> lcs_reverse_row(const vector<int>& a_rev, const vector<int>& b_rev) {
    int nb = b_rev.size();
    vector<int> prev(nb + 1, 0), curr(nb + 1, 0);
    for (size_t i = 0; i < a_rev.size(); i++) {
        for (int j = 1; j <= nb; j++) {
            curr[j] = (a_rev[i] == b_rev[j-1]) ? prev[j-1] + 1
                     : max(prev[j], curr[j-1]);
        }
        swap(prev, curr);
        fill(curr.begin(), curr.end(), 0);
    }
    return prev;
}

// Hirschberg recursive divide-and-conquer
vector<CharOp> hirschberg_rec(const vector<int>& a, const vector<int>& b) {
    int na = a.size(), nb = b.size();
    vector<CharOp> result;

    if (na == 0) {
        for (int j = 0; j < nb; j++)
            result.push_back({2, b[j]});
        return result;
    }
    if (nb == 0) {
        for (int i = 0; i < na; i++)
            result.push_back({1, a[i]});
        return result;
    }
    if (na == 1) {
        // Single char in a: check if it's in b
        bool found = false;
        for (int j = 0; j < nb; j++) {
            if (!found && a[0] == b[j]) {
                result.push_back({0, a[0]});
                found = true;
            } else {
                result.push_back({2, b[j]});
            }
        }
        if (!found) {
            result.insert(result.begin(), {1, a[0]});
        }
        return result;
    }

    // Split a in half
    int mid = na / 2;
    vector<int> a_left(a.begin(), a.begin() + mid);
    vector<int> a_right(a.begin() + mid, a.end());

    // Forward LCS for left half
    vector<int> fwd = lcs_forward_row(a_left, b);

    // Reverse LCS for right half
    vector<int> a_right_rev(a_right.rbegin(), a_right.rend());
    vector<int> b_rev(b.rbegin(), b.rend());
    vector<int> rev = lcs_reverse_row(a_right_rev, b_rev);

    // Find optimal split point j_opt that maximizes fwd[j] + rev[nb - j]
    int j_opt = 0;
    int max_sum = -1;
    for (int j = 0; j <= nb; j++) {
        int sum = fwd[j] + rev[nb - j];
        if (sum > max_sum) {
            max_sum = sum;
            j_opt = j;
        }
    }

    // Split b
    vector<int> b_left(b.begin(), b.begin() + j_opt);
    vector<int> b_right(b.begin() + j_opt, b.end());

    // Recurse
    vector<CharOp> left_ops = hirschberg_rec(a_left, b_left);
    vector<CharOp> right_ops = hirschberg_rec(a_right, b_right);

    // Combine
    result.reserve(left_ops.size() + right_ops.size());
    result.insert(result.end(), left_ops.begin(), left_ops.end());
    result.insert(result.end(), right_ops.begin(), right_ops.end());
    return result;
}

vector<CharOp> hirschberg_lcs(const vector<int>& a, const vector<int>& b) {
    return hirschberg_rec(a, b);
}

// --- Cache-friendly standard LCS (row traversal, 2 rows) ---
// This is the same algorithm as standard_lcs but uses only 2 rows
// (O(n) space) instead of the full 2D table (O(n*m) space).
// It still needs O(n*m) TIME but the cache behavior is better.
//
// HOWEVER: it can't backtrack without the full table, so it does
// TWO passes: first to find the LCS length, then Hirschberg to
// reconstruct. This is essentially a hybrid.
//
// For the benchmark, we'll just measure the forward DP pass.

vector<int> cache_friendly_lcs_length(const vector<int>& a, const vector<int>& b) {
    return lcs_forward_row(a, b);
}

// --- Test harness ---

size_t get_peak_rss_kb() {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    return ru.ru_maxrss;  // KB on Linux
}

int main() {
    // Test with various sizes
    for (int size : {100, 500, 1000, 2000, 5000}) {
        // Generate random-ish test data
        vector<int> a(size), b(size);
        for (int i = 0; i < size; i++) {
            a[i] = (i * 7 + 13) % 256;
            b[i] = (i * 3 + 17) % 256;
        }
        // Make them ~70% similar
        for (int i = 0; i < size; i++) {
            if (i % 10 < 7) b[i] = a[i];  // 70% same
        }

        printf("=== Size %d ===\n", size);
        size_t rss_before = get_peak_rss_kb();

        // Standard LCS
        auto t0 = Clock::now();
        auto ops_std = standard_lcs(a, b);
        auto t1 = Clock::now();
        size_t rss_after_std = get_peak_rss_kb();
        double ms_std = chrono::duration<double, milli>(t1 - t0).count();

        // Hirschberg LCS
        auto t2 = Clock::now();
        auto ops_hir = hirschberg_lcs(a, b);
        auto t3 = Clock::now();
        size_t rss_after_hir = get_peak_rss_kb();
        double ms_hir = chrono::duration<double, milli>(t3 - t2).count();

        // Cache-friendly forward pass only (for comparison)
        auto t4 = Clock::now();
        auto fwd = cache_friendly_lcs_length(a, b);
        auto t5 = Clock::now();
        double ms_cache = chrono::duration<double, milli>(t5 - t4).count();

        // Verify both produce same number of keep/delete/insert
        int std_k=0, std_d=0, std_i=0;
        for (auto& op : ops_std) {
            if (op.type == 0) std_k++; else if (op.type == 1) std_d++; else std_i++;
        }
        int hir_k=0, hir_d=0, hir_i=0;
        for (auto& op : ops_hir) {
            if (op.type == 0) hir_k++; else if (op.type == 1) hir_d++; else hir_i++;
        }

        printf("  Standard:   %8.1f ms  keep=%d del=%d ins=%d  RSS=%zu KB\n",
               ms_std, std_k, std_d, std_i, rss_after_std);
        printf("  Hirschberg: %8.1f ms  keep=%d del=%d ins=%d  RSS=%zu KB\n",
               ms_hir, hir_k, hir_d, hir_i, rss_after_hir);
        printf("  Cache-2row: %8.1f ms  (forward pass only, LCS=%d)\n",
               ms_cache, fwd[size]);
        printf("  Match: %s\n", (std_k == hir_k && std_d == hir_d && std_i == hir_i) ? "YES" : "NO");
        printf("\n");
    }
    return 0;
}
