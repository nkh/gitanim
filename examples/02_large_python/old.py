#!/usr/bin/env python3
"""Data processor module — handles CSV ingestion and transformation."""

import csv
import os
import sys
from typing import List, Dict, Optional


class DataProcessor:
    """Processes CSV data with configurable transformations."""

    def __init__(self, config: Dict):
        self.config = config
        self.data: List[Dict] = []
        self.errors: List[str] = []

    def load_csv(self, filepath: str) -> bool:
        """Load data from a CSV file."""
        if not os.path.exists(filepath):
            self.errors.append(f"File not found: {filepath}")
            return False

        try:
            with open(filepath, 'r', newline='') as f:
                reader = csv.DictReader(f)
                self.data = [row for row in reader]
        except csv.Error as e:
            self.errors.append(f"CSV parse error: {e}")
            return False

        return True

    def transform(self, column: str, func) -> None:
        """Apply a transformation function to a column."""
        for row in self.data:
            if column in row:
                try:
                    row[column] = func(row[column])
                except (ValueError, TypeError) as e:
                    self.errors.append(f"Transform error on row: {e}")

    def filter_rows(self, predicate) -> List[Dict]:
        """Filter rows based on a predicate function."""
        return [row for row in self.data if predicate(row)]

    def get_column(self, name: str) -> List:
        """Extract a single column as a list."""
        return [row.get(name) for row in self.data]

    def summary(self) -> Dict:
        """Return a summary of the processed data."""
        return {
            'total_rows': len(self.data),
            'columns': list(self.data[0].keys()) if self.data else [],
            'errors': len(self.errors),
        }


def main():
    config = {'verbose': True}
    processor = DataProcessor(config)

    if processor.load_csv(sys.argv[1] if len(sys.argv) > 1 else 'data.csv'):
        processor.transform('amount', lambda x: float(x))
        processor.transform('date', lambda x: x.strip())

        valid = processor.filter_rows(lambda r: r.get('amount', 0) > 0)
        print(f"Valid rows: {len(valid)}")
        print(f"Summary: {processor.summary()}")
    else:
        print("Errors:", processor.errors)


if __name__ == '__main__':
    main()
