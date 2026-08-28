#!/usr/bin/env python3
"""Data processor module — handles CSV/JSON ingestion and transformation."""

import csv
import json
import os
import sys
from pathlib import Path
from typing import List, Dict, Optional, Any, Callable, Iterator
from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class ProcessingResult:
    """Result of a data processing operation."""
    success: bool
    rows_processed: int = 0
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)


class DataProcessor:
    """Processes CSV/JSON data with configurable transformations."""

    def __init__(self, config: Optional[Dict] = None):
        self.config = config or {}
        self.data: List[Dict[str, Any]] = []
        self.errors: List[str] = []
        self._result = ProcessingResult(success=True)

    def load_csv(self, filepath: str | Path) -> bool:
        """Load data from a CSV file."""
        path = Path(filepath)
        if not path.exists():
            self.errors.append(f"File not found: {path}")
            self._result.success = False
            return False

        try:
            with open(path, 'r', newline='', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                self.data = list(reader)
                self._result.rows_processed = len(self.data)
        except csv.Error as e:
            self.errors.append(f"CSV parse error: {e}")
            self._result.success = False
            return False

        return True

    def load_json(self, filepath: str | Path) -> bool:
        """Load data from a JSON file (array of objects)."""
        path = Path(filepath)
        if not path.exists():
            self.errors.append(f"File not found: {path}")
            return False

        try:
            with open(path, 'r', encoding='utf-8') as f:
                self.data = json.load(f)
        except json.JSONDecodeError as e:
            self.errors.append(f"JSON parse error: {e}")
            return False

        return True

    def transform(self, column: str, func: Callable) -> None:
        """Apply a transformation function to a column."""
        for row in self.data:
            if column in row:
                try:
                    row[column] = func(row[column])
                except (ValueError, TypeError) as e:
                    self.errors.append(f"Transform error: {e}")

    def filter_rows(self, predicate: Callable) -> List[Dict]:
        """Filter rows based on a predicate function."""
        return [row for row in self.data if predicate(row)]

    def get_column(self, name: str) -> List[Any]:
        """Extract a single column as a list."""
        return [row.get(name) for row in self.data]

    def summary(self) -> Dict[str, Any]:
        """Return a summary of the processed data."""
        return {
            'total_rows': len(self.data),
            'columns': list(self.data[0].keys()) if self.data else [],
            'errors': len(self.errors),
            'timestamp': datetime.now().isoformat(),
        }

    @property
    def result(self) -> ProcessingResult:
        return self._result


def main():
    config = {'verbose': True, 'format': 'csv'}
    processor = DataProcessor(config)

    input_file = sys.argv[1] if len(sys.argv) > 1 else 'data.csv'

    if input_file.endswith('.json'):
        loaded = processor.load_json(input_file)
    else:
        loaded = processor.load_csv(input_file)

    if loaded:
        processor.transform('amount', float)
        processor.transform('date', lambda x: x.strip())

        valid = processor.filter_rows(lambda r: r.get('amount', 0) > 0)
        print(f"Valid rows: {len(valid)}")
        print(f"Summary: {processor.summary()}")
    else:
        print("Errors:", processor.errors)
        sys.exit(1)


if __name__ == '__main__':
    main()
