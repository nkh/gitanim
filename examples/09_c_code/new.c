#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    int nums[] = {1, 2, 3, 4, 5};
    int n = sizeof(nums) / sizeof(nums[0]);
    int sum = 0;

    for (int i = 0; i < n; i++) {
        sum += nums[i];
    }

    double avg = (double)sum / n;
    printf("Sum: %d\n", sum);
    printf("Average: %.2f\n", avg);

    return 0;
}
