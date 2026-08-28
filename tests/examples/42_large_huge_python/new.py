#!/usr/bin/env python3
"""Data pipeline — refactored.

Splits the original 1000-line monolith into well-typed modules with proper
configuration, structured logging, exception hierarchy, and dependency
injection. Each stage (extract, transform, load, report, validate) is
implemented as a class so it can be tested and composed independently.
"""

from __future__ import annotations

import abc
import csv
import dataclasses
import datetime as dt
import hashlib
import json
import logging
import os
import smtplib
import sqlite3
import statistics
import sys
import time
from collections import defaultdict
from contextlib import contextmanager
from email.mime.text import MIMEText
from pathlib import Path
from typing import (
    Any, Callable, Dict, Iterable, Iterator, List, Optional, Sequence,
    Set, Tuple, Type, TypeVar,
)
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

log = logging.getLogger(__name__)

T = TypeVar('T')


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class PipelineConfig:
    """Immutable pipeline configuration loaded from env vars or a dict."""
    customers_csv: Path
    orders_api_url: str
    orders_api_key: str
    products_db: Path
    returns_json: Path
    warehouse_db: Path
    reports_dir: Path
    since: Optional[str]
    alert_recipients: List[str]
    api_page_size: int = 100
    api_max_pages: int = 1000
    api_rate_limit_seconds: float = 0.1
    api_timeout_seconds: int = 30
    chunk_size: int = 500
    max_retry_attempts: int = 3
    retry_backoff_base: float = 1.0
    retry_backoff_factor: float = 2.0
    alert_failure_threshold: int = 100
    alert_error_threshold: int = 50
    alert_runtime_seconds: int = 3600

    @classmethod
    def from_env(cls, env: Optional[Dict[str, str]] = None) -> 'PipelineConfig':
        env = env or os.environ
        return cls(
            customers_csv=Path(env.get('CUSTOMERS_CSV', 'data/customers.csv')),
            orders_api_url=env.get('ORDERS_API_URL', 'http://localhost:4000/api/orders'),
            orders_api_key=env.get('ORDERS_API_KEY', ''),
            products_db=Path(env.get('PRODUCTS_DB', 'data/products.db')),
            returns_json=Path(env.get('RETURNS_JSON', 'data/returns.json')),
            warehouse_db=Path(env.get('WAREHOUSE_DB', 'data/warehouse.db')),
            reports_dir=Path(env.get('REPORTS_DIR', 'reports')),
            since=env.get('SINCE') or None,
            alert_recipients=[
                r for r in env.get('ALERT_RECIPIENTS', '').split(',') if r
            ],
            api_page_size=int(env.get('API_PAGE_SIZE', '100')),
            api_max_pages=int(env.get('API_MAX_PAGES', '1000')),
        )


# ---------------------------------------------------------------------------
# Domain types (typed records)
# ---------------------------------------------------------------------------

@dataclasses.dataclass
class Customer:
    customer_id: str
    name: str
    email: str
    country: str
    signup_date: str
    segment: str = 'standard'
    lifetime_value: float = 0.0
    order_count: int = 0
    last_order_date: Optional[str] = None


@dataclasses.dataclass
class Product:
    product_id: str
    sku: str
    name: str
    category: str
    unit_price: float
    cost: float
    inventory_count: int
    discontinued: bool = False


@dataclasses.dataclass
class OrderItem:
    product_id: str
    quantity: int
    unit_price: float
    total_price: float


@dataclasses.dataclass
class Order:
    order_id: str
    customer_id: str
    order_date: str
    status: str
    subtotal: float
    discount: float
    tax: float
    shipping: float
    total: float
    item_count: int
    payment_method: str
    channel: str
    returned_amount: float
    line_items: List[OrderItem]


@dataclasses.dataclass
class ReturnRecord:
    order_id: str
    refund_amount: float
    reason: str = ''


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class PipelineError(Exception):
    """Base class for pipeline errors."""


class ExtractError(PipelineError):
    """Raised when a source cannot be read."""


class TransformError(PipelineError):
    """Raised when a record cannot be transformed."""


class LoadError(PipelineError):
    """Raised when records cannot be written to the warehouse."""


class ConfigError(PipelineError):
    """Raised when configuration is invalid."""


# ---------------------------------------------------------------------------
# Metrics & run state
# ---------------------------------------------------------------------------

@dataclasses.dataclass
class PipelineMetrics:
    customer_count: int = 0
    order_count: int = 0
    product_count: int = 0
    return_count: int = 0
    processed_records: int = 0
    failed_records: int = 0
    error_count: int = 0
    runtime_seconds: float = 0.0
    warehouse_customers: int = 0
    warehouse_products: int = 0
    warehouse_orders: int = 0
    warehouse_order_items: int = 0
    avg_order_value: float = 0.0
    median_order_value: float = 0.0
    max_order_value: float = 0.0
    min_order_value: float = 0.0
    total_revenue: float = 0.0
    avg_ltv: float = 0.0
    median_ltv: float = 0.0
    max_ltv: float = 0.0
    total_ltv: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return dataclasses.asdict(self)


@dataclasses.dataclass
class PipelineRunResult:
    run_id: str
    status: str
    metrics: PipelineMetrics
    quality_issues: List[str]
    errors: List[str]


# ---------------------------------------------------------------------------
# Warehouse connection
# ---------------------------------------------------------------------------

class Warehouse:
    """Thin wrapper around sqlite3.Connection with schema management."""

    SCHEMA_SQL = '''
        CREATE TABLE IF NOT EXISTS dim_customers (
            customer_id TEXT PRIMARY KEY,
            name TEXT,
            email TEXT,
            country TEXT,
            signup_date TEXT,
            segment TEXT,
            lifetime_value REAL,
            order_count INTEGER,
            last_order_date TEXT,
            updated_at TEXT
        );
        CREATE TABLE IF NOT EXISTS dim_products (
            product_id TEXT PRIMARY KEY,
            sku TEXT,
            name TEXT,
            category TEXT,
            unit_price REAL,
            cost REAL,
            inventory_count INTEGER,
            discontinued INTEGER,
            updated_at TEXT
        );
        CREATE TABLE IF NOT EXISTS fact_orders (
            order_id TEXT PRIMARY KEY,
            customer_id TEXT,
            order_date TEXT,
            status TEXT,
            subtotal REAL,
            discount REAL,
            tax REAL,
            shipping REAL,
            total REAL,
            item_count INTEGER,
            payment_method TEXT,
            channel TEXT,
            inserted_at TEXT
        );
        CREATE TABLE IF NOT EXISTS fact_order_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id TEXT,
            product_id TEXT,
            quantity INTEGER,
            unit_price REAL,
            total_price REAL,
            category TEXT
        );
        CREATE TABLE IF NOT EXISTS pipeline_runs (
            run_id TEXT PRIMARY KEY,
            started_at TEXT,
            finished_at TEXT,
            status TEXT,
            processed INTEGER,
            failed INTEGER,
            errors TEXT
        );
    '''

    def __init__(self, path: Path) -> None:
        self._path = path
        self._conn: Optional[sqlite3.Connection] = None

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        """Open a connection for the duration of the context manager."""
        if self._conn is None:
            self._conn = sqlite3.connect(str(self._path))
            self._conn.row_factory = sqlite3.Row
            self._conn.execute('PRAGMA journal_mode=WAL')
        try:
            yield self._conn
            self._conn.commit()
        except Exception:
            if self._conn is not None:
                self._conn.rollback()
            raise

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def init_schema(self) -> None:
        with self.connect() as conn:
            conn.executescript(self.SCHEMA_SQL)

    def upsert_customer(self, customer: Customer) -> None:
        with self.connect() as conn:
            conn.execute('''
                INSERT INTO dim_customers
                (customer_id, name, email, country, signup_date, segment,
                 lifetime_value, order_count, last_order_date, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(customer_id) DO UPDATE SET
                    name=excluded.name, email=excluded.email,
                    country=excluded.country, signup_date=excluded.signup_date,
                    segment=excluded.segment, lifetime_value=excluded.lifetime_value,
                    order_count=excluded.order_count,
                    last_order_date=excluded.last_order_date,
                    updated_at=excluded.updated_at
            ''', (
                customer.customer_id, customer.name, hash_pii(customer.email),
                customer.country, customer.signup_date, customer.segment,
                customer.lifetime_value, customer.order_count,
                customer.last_order_date, utcnow_iso(),
            ))

    def upsert_product(self, product: Product) -> None:
        with self.connect() as conn:
            conn.execute('''
                INSERT INTO dim_products
                (product_id, sku, name, category, unit_price, cost,
                 inventory_count, discontinued, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(product_id) DO UPDATE SET
                    sku=excluded.sku, name=excluded.name, category=excluded.category,
                    unit_price=excluded.unit_price, cost=excluded.cost,
                    inventory_count=excluded.inventory_count,
                    discontinued=excluded.discontinued, updated_at=excluded.updated_at
            ''', (
                product.product_id, product.sku, product.name, product.category,
                product.unit_price, product.cost, product.inventory_count,
                1 if product.discontinued else 0, utcnow_iso(),
            ))

    def insert_order(self, order: Order) -> None:
        with self.connect() as conn:
            conn.execute('''
                INSERT OR REPLACE INTO fact_orders
                (order_id, customer_id, order_date, status, subtotal, discount,
                 tax, shipping, total, item_count, payment_method, channel,
                 inserted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                order.order_id, order.customer_id, order.order_date, order.status,
                order.subtotal, order.discount, order.tax, order.shipping,
                order.total, order.item_count, order.payment_method, order.channel,
                utcnow_iso(),
            ))

    def insert_order_items(self, items: Sequence[Dict[str, Any]]) -> None:
        if not items:
            return
        with self.connect() as conn:
            conn.executemany('''
                INSERT INTO fact_order_items
                (order_id, product_id, quantity, unit_price, total_price, category)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', [(
                item['order_id'], item['product_id'], item['quantity'],
                item['unit_price'], item['total_price'], item['category'],
            ) for item in items])

    def record_run(self, result: PipelineRunResult) -> None:
        with self.connect() as conn:
            conn.execute('''
                INSERT INTO pipeline_runs
                (run_id, started_at, finished_at, status, processed, failed, errors)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (
                result.run_id,
                (dt.datetime.utcnow() - dt.timedelta(seconds=result.metrics.runtime_seconds)).isoformat(),
                utcnow_iso(),
                result.status,
                result.metrics.processed_records,
                result.metrics.failed_records,
                '\n'.join(result.errors[:100]),
            ))

    def query(self, sql: str, params: Sequence[Any] = ()) -> List[sqlite3.Row]:
        with self.connect() as conn:
            return conn.execute(sql, params).fetchall()


# ---------------------------------------------------------------------------
# Extractors — each source has its own class implementing the Extractor
# interface.
# ---------------------------------------------------------------------------

class Extractor(abc.ABC, Generic[T]):
    @abc.abstractmethod
    def extract(self) -> List[T]:
        ...


class CustomerCsvExtractor(Extractor[Customer]):
    def __init__(self, path: Path) -> None:
        self._path = path

    def extract(self) -> List[Customer]:
        if not self._path.exists():
            raise ExtractError(f'customers CSV not found: {self._path}')
        customers: List[Customer] = []
        try:
            with self._path.open('r', newline='', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    try:
                        customer = Customer(
                            customer_id=row['customer_id'].strip(),
                            name=row['name'].strip(),
                            email=row['email'].strip().lower(),
                            country=row['country'].strip().upper(),
                            signup_date=row['signup_date'].strip(),
                            segment=row.get('segment', 'standard').strip().lower(),
                        )
                    except KeyError as e:
                        raise TransformError(
                            f'customer row missing column {e}: {row}'
                        ) from e
                    if not customer.customer_id or not customer.email:
                        log.warning('skipping customer with missing required field: %s', row)
                        continue
                    customers.append(customer)
        except OSError as e:
            raise ExtractError(f'failed to read customers CSV: {e}') from e
        log.info('loaded %d customers from %s', len(customers), self._path)
        return customers


class ProductDbExtractor(Extractor[Product]):
    def __init__(self, path: Path) -> None:
        self._path = path

    def extract(self) -> List[Product]:
        if not self._path.exists():
            raise ExtractError(f'products DB not found: {self._path}')
        try:
            with sqlite3.connect(str(self._path)) as conn:
                conn.row_factory = sqlite3.Row
                cur = conn.execute('SELECT * FROM products')
                products = [self._row_to_product(row) for row in cur.fetchall()]
        except sqlite3.Error as e:
            raise ExtractError(f'failed to read products DB: {e}') from e
        log.info('loaded %d products from %s', len(products), self._path)
        return products

    @staticmethod
    def _row_to_product(row: sqlite3.Row) -> Product:
        return Product(
            product_id=str(row['product_id'] or row['id']),
            sku=row['sku'],
            name=row['name'],
            category=row['category'],
            unit_price=float(row['unit_price'] or 0),
            cost=float(row['cost'] or 0),
            inventory_count=int(row['inventory_count'] or 0),
            discontinued=bool(row['discontinued']),
        )


class ReturnsJsonExtractor(Extractor[ReturnRecord]):
    def __init__(self, path: Path) -> None:
        self._path = path

    def extract(self) -> List[ReturnRecord]:
        if not self._path.exists():
            log.info('returns JSON not found, skipping: %s', self._path)
            return []
        try:
            with self._path.open('r', encoding='utf-8') as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            raise ExtractError(f'failed to read returns JSON: {e}') from e
        records = [
            ReturnRecord(
                order_id=str(r.get('order_id', '')),
                refund_amount=float(r.get('refund_amount', 0)),
                reason=str(r.get('reason', '')),
            )
            for r in data.get('returns', [])
        ]
        log.info('loaded %d returns from %s', len(records), self._path)
        return records


class OrdersApiExtractor(Extractor[Dict[str, Any]]):
    """Extracts raw order dicts from the orders API.

    Pagination, rate-limiting, and retry are handled here so the transformer
    can focus on shape conversion.
    """

    def __init__(self, base_url: str, api_key: str,
                 page_size: int = 100, max_pages: int = 1000,
                 rate_limit_seconds: float = 0.1,
                 timeout_seconds: int = 30,
                 since: Optional[str] = None,
                 max_attempts: int = 3,
                 backoff_base: float = 1.0,
                 backoff_factor: float = 2.0) -> None:
        self._base_url = base_url
        self._api_key = api_key
        self._page_size = page_size
        self._max_pages = max_pages
        self._rate_limit = rate_limit_seconds
        self._timeout = timeout_seconds
        self._since = since
        self._max_attempts = max_attempts
        self._backoff_base = backoff_base
        self._backoff_factor = backoff_factor

    def extract(self) -> List[Dict[str, Any]]:
        all_orders: List[Dict[str, Any]] = []
        page = 1
        while page <= self._max_pages:
            try:
                page_orders = self._fetch_page(page)
            except ExtractError as e:
                log.error('orders API page %d failed: %s', page, e)
                break
            if not page_orders:
                break
            all_orders.extend(page_orders)
            if len(page_orders) < self._page_size:
                break
            page += 1
            time.sleep(self._rate_limit)
        else:
            log.warning('orders API: exceeded %d pages, aborting pagination', self._max_pages)
        log.info('loaded %d orders from %s', len(all_orders), self._base_url)
        return all_orders

    def _fetch_page(self, page: int) -> List[Dict[str, Any]]:
        url = f'{self._base_url}?page={page}&per_page={self._page_size}'
        if self._since:
            url += f'&since={self._since}'
        req = Request(url, headers={
            'Authorization': f'Bearer {self._api_key}',
            'Accept': 'application/json',
        })
        delay = self._backoff_base
        last_exc: Optional[Exception] = None
        for attempt in range(1, self._max_attempts + 1):
            try:
                with urlopen(req, timeout=self._timeout) as resp:
                    data = json.loads(resp.read().decode('utf-8'))
                return data.get('orders', [])
            except HTTPError as e:
                last_exc = e
                log.warning('orders API HTTP error (attempt %d/%d): %s',
                            attempt, self._max_attempts, e)
            except URLError as e:
                last_exc = e
                log.warning('orders API URL error (attempt %d/%d): %s',
                            attempt, self._max_attempts, e)
            except Exception as e:
                last_exc = e
                log.warning('orders API error (attempt %d/%d): %s',
                            attempt, self._max_attempts, e)
            if attempt < self._max_attempts:
                time.sleep(delay)
                delay *= self._backoff_factor
        raise ExtractError(f'orders API page {page} failed after {self._max_attempts} attempts: {last_exc}')


# ---------------------------------------------------------------------------
# Transformers
# ---------------------------------------------------------------------------

class OrderTransformer:
    """Converts raw API order dicts into typed Order records."""

    def __init__(self, products_by_id: Dict[str, Product],
                 returns_by_order: Dict[str, List[ReturnRecord]]) -> None:
        self._products_by_id = products_by_id
        self._returns_by_order = returns_by_order

    def transform(self, raw_orders: Sequence[Dict[str, Any]]) -> Tuple[List[Order], int]:
        orders: List[Order] = []
        failed = 0
        seen_ids: Set[str] = set()
        for raw in raw_orders:
            try:
                order = self._transform_one(raw)
            except TransformError as e:
                log.warning('skipping order: %s', e)
                failed += 1
                continue
            if order.order_id in seen_ids:
                log.warning('skipping duplicate order: %s', order.order_id)
                continue
            if not order.order_id or not order.customer_id:
                log.warning('skipping order with missing id: %s', order.order_id)
                failed += 1
                continue
            if not order.order_date:
                log.warning('skipping order without date: %s', order.order_id)
                failed += 1
                continue
            seen_ids.add(order.order_id)
            orders.append(order)
        return orders, failed

    def _transform_one(self, raw: Dict[str, Any]) -> Order:
        try:
            subtotal = float(raw.get('subtotal', 0))
            discount = float(raw.get('discount_amount', 0))
            tax = float(raw.get('tax_amount', 0))
            shipping = float(raw.get('shipping_amount', 0))
            total = float(raw.get('total', subtotal - discount + tax + shipping))
        except (ValueError, TypeError) as e:
            raise TransformError(
                f'bad order totals for {raw.get("id")}: {e}'
            ) from e

        line_items = self._transform_items(raw.get('line_items', []))
        item_count = sum(item.quantity for item in line_items)
        returns = self._returns_by_order.get(str(raw.get('id')), [])
        returned_amount = sum(r.refund_amount for r in returns)
        return Order(
            order_id=str(raw.get('id')),
            customer_id=str(raw.get('customer_id')),
            order_date=raw.get('order_date') or raw.get('created_at') or '',
            status=raw.get('status', 'unknown'),
            subtotal=subtotal, discount=discount, tax=tax, shipping=shipping,
            total=total, item_count=item_count,
            payment_method=raw.get('payment_method', 'unknown'),
            channel=raw.get('channel', 'web'),
            returned_amount=returned_amount,
            line_items=line_items,
        )

    def _transform_items(self, raw_items: Sequence[Dict[str, Any]]) -> List[OrderItem]:
        items: List[OrderItem] = []
        for raw in raw_items:
            product_id = str(raw.get('product_id'))
            product = self._products_by_id.get(product_id)
            try:
                items.append(OrderItem(
                    product_id=product_id,
                    quantity=int(raw.get('quantity', 0)),
                    unit_price=float(raw.get('unit_price', product.unit_price if product else 0)),
                    total_price=float(raw.get('total_price', 0)),
                ))
            except (ValueError, TypeError) as e:
                raise TransformError(
                    f'bad line item for product {product_id}: {e}'
                ) from e
        return items

    def enrich_items_for_warehouse(self, order: Order) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []
        for item in order.line_items:
            product = self._products_by_id.get(item.product_id)
            items.append({
                'order_id': order.order_id,
                'product_id': item.product_id,
                'quantity': item.quantity,
                'unit_price': item.unit_price,
                'total_price': item.total_price,
                'category': product.category if product else 'unknown',
            })
        return items


class CustomerEnricher:
    """Computes lifetime value and assigns customer segments."""

    def __init__(self, orders: Sequence[Order]) -> None:
        self._orders = orders

    def enrich(self, customer: Customer) -> Customer:
        total = 0.0
        order_count = 0
        last_order_date: Optional[str] = None
        for order in self._orders:
            if order.customer_id != customer.customer_id:
                continue
            if order.status in ('paid', 'shipped', 'delivered'):
                total += order.total
                order_count += 1
                if last_order_date is None or order.order_date > last_order_date:
                    last_order_date = order.order_date
        customer.lifetime_value = round(total, 2)
        customer.order_count = order_count
        customer.last_order_date = last_order_date
        customer.segment = self._segment(customer)
        return customer

    @staticmethod
    def _segment(customer: Customer) -> str:
        if customer.lifetime_value > 5000 or customer.order_count > 50:
            return 'platinum'
        if customer.lifetime_value > 1000 or customer.order_count > 10:
            return 'gold'
        if customer.lifetime_value > 100 or customer.order_count > 0:
            return 'silver'
        return 'bronze'


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------

class WarehouseLoader:
    """Writes typed records to the warehouse in batches."""

    def __init__(self, warehouse: Warehouse, chunk_size: int = 500) -> None:
        self._warehouse = warehouse
        self._chunk_size = chunk_size

    def load_customers(self, customers: Sequence[Customer]) -> None:
        for chunk in chunked(customers, self._chunk_size):
            for customer in chunk:
                self._warehouse.upsert_customer(customer)
        log.info('loaded %d customers into warehouse', len(customers))

    def load_products(self, products: Sequence[Product]) -> None:
        for chunk in chunked(products, self._chunk_size):
            for product in chunk:
                self._warehouse.upsert_product(product)
        log.info('loaded %d products into warehouse', len(products))

    def load_orders(self, orders: Sequence[Order],
                    transformer: OrderTransformer) -> None:
        all_items: List[Dict[str, Any]] = []
        for order in orders:
            self._warehouse.insert_order(order)
            all_items.extend(transformer.enrich_items_for_warehouse(order))
        for chunk in chunked(all_items, self._chunk_size):
            self._warehouse.insert_order_items(chunk)
        log.info('loaded %d orders (%d items) into warehouse',
                 len(orders), len(all_items))


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

class ReportWriter(abc.ABC):
    @abc.abstractmethod
    def write(self, warehouse: Warehouse, output_path: Path) -> None:
        ...


class CsvQueryReport(ReportWriter):
    """Runs a SQL query and writes the result to a CSV file."""

    def __init__(self, name: str, sql: str,
                 headers: Sequence[str],
                 params: Sequence[Any] = ()) -> None:
        self._name = name
        self._sql = sql
        self._headers = headers
        self._params = params

    def write(self, warehouse: Warehouse, output_path: Path) -> None:
        rows = warehouse.query(self._sql, self._params)
        with output_path.open('w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(self._headers)
            for row in rows:
                writer.writerow([row[h] if isinstance(h, str) and h in row.keys() else h
                                 for h in self._headers])
        log.info('wrote %d rows to %s', len(rows), output_path)


class ReportSuite:
    """Bundles a set of reports to run on each pipeline run."""

    @staticmethod
    def default() -> List[ReportWriter]:
        return [
            CsvQueryReport('revenue', '''
                SELECT strftime('%Y-%m', order_date) AS month, COUNT(*) AS order_count,
                       SUM(subtotal) AS subtotal, SUM(discount) AS discount,
                       SUM(tax) AS tax, SUM(shipping) AS shipping, SUM(total) AS total
                FROM fact_orders GROUP BY month ORDER BY month
            ''', ['month', 'order_count', 'subtotal', 'discount', 'tax', 'shipping', 'total']),
            CsvQueryReport('segments', '''
                SELECT segment, COUNT(*) AS customer_count, AVG(lifetime_value) AS avg_ltv,
                       SUM(lifetime_value) AS total_ltv
                FROM dim_customers GROUP BY segment ORDER BY total_ltv DESC
            ''', ['segment', 'customer_count', 'avg_ltv', 'total_ltv']),
            CsvQueryReport('top_products', '''
                SELECT p.product_id, p.name, p.category,
                       SUM(oi.quantity) AS units_sold, SUM(oi.total_price) AS revenue
                FROM dim_products p
                LEFT JOIN fact_order_items oi ON oi.product_id = p.product_id
                GROUP BY p.product_id ORDER BY revenue DESC LIMIT 100
            ''', ['product_id', 'name', 'category', 'units_sold', 'revenue']),
            CsvQueryReport('cohorts', '''
                SELECT c.signup_date AS signup_month,
                       strftime('%Y-%m', o.order_date) AS order_month,
                       COUNT(DISTINCT o.order_id) AS orders
                FROM dim_customers c
                LEFT JOIN fact_orders o ON o.customer_id = c.customer_id
                WHERE c.signup_date IS NOT NULL
                GROUP BY signup_month, order_month
                ORDER BY signup_month, order_month
            ''', ['signup_month', 'order_month', 'orders']),
            CsvQueryReport('funnel', '''
                SELECT status, COUNT(*) AS n, SUM(total) AS revenue
                FROM fact_orders GROUP BY status ORDER BY revenue DESC
            ''', ['status', 'n', 'revenue']),
            CsvQueryReport('geo', '''
                SELECT c.country, COUNT(DISTINCT o.order_id) AS orders,
                       SUM(o.total) AS revenue, COUNT(DISTINCT c.customer_id) AS customers
                FROM dim_customers c
                LEFT JOIN fact_orders o ON o.customer_id = c.customer_id
                GROUP BY c.country ORDER BY revenue DESC
            ''', ['country', 'orders', 'revenue', 'customers']),
        ]

    @staticmethod
    def write_all(reports: Sequence[ReportWriter], warehouse: Warehouse,
                  reports_dir: Path) -> None:
        reports_dir.mkdir(parents=True, exist_ok=True)
        for report in reports:
            name = getattr(report, '_name', 'report')
            path = reports_dir / f'{name}.csv'
            try:
                report.write(warehouse, path)
            except Exception as e:
                log.error('failed to write report %s: %s', name, e)


# ---------------------------------------------------------------------------
# Data quality
# ---------------------------------------------------------------------------

class QualityChecker:
    """Runs a series of checks against the warehouse and produces a list of
    human-readable issues."""

    def __init__(self) -> None:
        self._checks: List[Callable[[Warehouse, Sequence[Customer], Sequence[Order]], List[str]]] = [
            self.check_referential_integrity,
            self.validate_order_totals,
            self.check_customer_segments,
            self.check_date_ranges,
        ]

    def run(self, warehouse: Warehouse, customers: Sequence[Customer],
            orders: Sequence[Order]) -> List[str]:
        issues: List[str] = []
        for check in self._checks:
            try:
                issues.extend(check(warehouse, customers, orders))
            except Exception as e:
                log.error('quality check %s failed: %s', check.__name__, e)
                issues.append(f'check {check.__name__} crashed: {e}')
        return issues

    @staticmethod
    def check_referential_integrity(warehouse: Warehouse,
                                    customers: Sequence[Customer],
                                    orders: Sequence[Order]) -> List[str]:
        issues: List[str] = []
        rows = warehouse.query('''
            SELECT COUNT(*) AS n FROM fact_orders o
            LEFT JOIN dim_customers c ON c.customer_id = o.customer_id
            WHERE c.customer_id IS NULL
        ''')
        if rows and rows[0]['n'] > 0:
            issues.append(f"{rows[0]['n']} orders reference unknown customers")
        rows = warehouse.query('''
            SELECT COUNT(*) AS n FROM fact_order_items oi
            LEFT JOIN dim_products p ON p.product_id = oi.product_id
            WHERE p.product_id IS NULL
        ''')
        if rows and rows[0]['n'] > 0:
            issues.append(f"{rows[0]['n']} order items reference unknown products")
        rows = warehouse.query('SELECT COUNT(*) AS n FROM fact_orders WHERE total < 0')
        if rows and rows[0]['n'] > 0:
            issues.append(f"{rows[0]['n']} orders have negative totals")
        return issues

    @staticmethod
    def validate_order_totals(warehouse: Warehouse,
                              customers: Sequence[Customer],
                              orders: Sequence[Order]) -> List[str]:
        issues: List[str] = []
        for order in orders:
            expected = order.subtotal - order.discount + order.tax + order.shipping
            if abs(expected - order.total) > 0.01:
                issues.append(f'order {order.order_id} total mismatch: '
                              f'expected {expected:.2f}, got {order.total:.2f}')
        return issues

    @staticmethod
    def check_customer_segments(warehouse: Warehouse,
                                customers: Sequence[Customer],
                                orders: Sequence[Order]) -> List[str]:
        valid: Set[str] = {'platinum', 'gold', 'silver', 'bronze', 'standard'}
        return [
            f'customer {c.customer_id} has invalid segment: {c.segment}'
            for c in customers if c.segment not in valid
        ]

    @staticmethod
    def check_date_ranges(warehouse: Warehouse,
                          customers: Sequence[Customer],
                          orders: Sequence[Order]) -> List[str]:
        issues: List[str] = []
        today = dt.date.today().isoformat()
        one_year_ago = (dt.date.today() - dt.timedelta(days=365)).isoformat()
        for order in orders:
            if not order.order_date:
                continue
            if order.order_date > today:
                issues.append(f'order {order.order_id} has future date: {order.order_date}')
            elif order.order_date < one_year_ago:
                issues.append(f'order {order.order_id} has very old date: {order.order_date}')
        return issues

    @staticmethod
    def write_report(issues: Sequence[str], output_path: Path) -> None:
        with output_path.open('w', encoding='utf-8') as f:
            if not issues:
                f.write('No data quality issues found.\n')
                return
            f.write(f'{len(issues)} data quality issues found:\n\n')
            for i, issue in enumerate(issues, 1):
                f.write(f'{i}. {issue}\n')


# ---------------------------------------------------------------------------
# Metrics collection
# ---------------------------------------------------------------------------

class MetricsCollector:
    def __init__(self, warehouse: Warehouse) -> None:
        self._warehouse = warehouse

    def collect(self, customers: Sequence[Customer], orders: Sequence[Order],
                products: Sequence[Product], returns: Sequence[ReturnRecord],
                processed: int, failed: int, errors: int,
                runtime_seconds: float) -> PipelineMetrics:
        metrics = PipelineMetrics(
            customer_count=len(customers),
            order_count=len(orders),
            product_count=len(products),
            return_count=len(returns),
            processed_records=processed,
            failed_records=failed,
            error_count=errors,
            runtime_seconds=runtime_seconds,
        )
        for field, sql in [
            ('warehouse_customers', 'SELECT COUNT(*) AS n FROM dim_customers'),
            ('warehouse_products', 'SELECT COUNT(*) AS n FROM dim_products'),
            ('warehouse_orders', 'SELECT COUNT(*) AS n FROM fact_orders'),
            ('warehouse_order_items', 'SELECT COUNT(*) AS n FROM fact_order_items'),
        ]:
            rows = self._warehouse.query(sql)
            if rows:
                setattr(metrics, field, rows[0]['n'])
        if orders:
            totals = [o.total for o in orders]
            metrics.avg_order_value = statistics.mean(totals)
            metrics.median_order_value = statistics.median(totals)
            metrics.max_order_value = max(totals)
            metrics.min_order_value = min(totals)
            metrics.total_revenue = sum(totals)
        if customers:
            ltvs = [c.lifetime_value for c in customers]
            metrics.avg_ltv = statistics.mean(ltvs)
            metrics.median_ltv = statistics.median(ltvs)
            metrics.max_ltv = max(ltvs)
            metrics.total_ltv = sum(ltvs)
        return metrics


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

class AlertManager:
    def __init__(self, recipients: List[str],
                 failure_threshold: int = 100,
                 error_threshold: int = 50,
                 runtime_seconds: int = 3600,
                 smtp_host: str = 'localhost',
                 smtp_port: int = 25) -> None:
        self._recipients = recipients
        self._failure_threshold = failure_threshold
        self._error_threshold = error_threshold
        self._runtime_seconds = runtime_seconds
        self._smtp_host = smtp_host
        self._smtp_port = smtp_port

    def check(self, metrics: PipelineMetrics) -> None:
        if metrics.failed_records > self._failure_threshold:
            self._send('Pipeline alert: high failure rate',
                       f'{metrics.failed_records} failed records in last run')
        if metrics.error_count > self._error_threshold:
            self._send('Pipeline alert: high error count',
                       f'{metrics.error_count} errors logged in last run')
        if metrics.runtime_seconds > self._runtime_seconds:
            self._send('Pipeline alert: long runtime',
                       f'pipeline took {metrics.runtime_seconds:.0f} seconds')

    def _send(self, subject: str, body: str) -> None:
        if not self._recipients:
            return
        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = 'pipeline@example.com'
        msg['To'] = ', '.join(self._recipients)
        try:
            with smtplib.SMTP(self._smtp_host, self._smtp_port) as s:
                s.send_message(msg)
        except OSError as e:
            log.error('failed to send alert email: %s', e)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def hash_pii(value: str) -> str:
    return hashlib.sha256(value.encode('utf-8')).hexdigest()[:16] if value else ''


def utcnow_iso() -> str:
    return dt.datetime.utcnow().isoformat()


def chunked(iterable: Sequence[T], size: int) -> Iterator[Sequence[T]]:
    for i in range(0, len(iterable), size):
        yield iterable[i:i + size]


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s %(levelname)s %(name)s: %(message)s',
    )


# ---------------------------------------------------------------------------
# Pipeline orchestrator
# ---------------------------------------------------------------------------

class Pipeline:
    def __init__(self, config: PipelineConfig) -> None:
        self._config = config
        self._warehouse = Warehouse(config.warehouse_db)
        self._errors: List[str] = []
        self._processed = 0
        self._failed = 0
        self._start_time: Optional[float] = None

    def run(self) -> PipelineRunResult:
        self._start_time = time.time()
        log.info('pipeline starting')
        try:
            customers, orders, products, returns = self._extract()
            orders, failed = self._transform(orders, products, returns)
            self._failed += failed
            self._processed += len(orders)
            self._enrich_customers(customers, orders)
            self._load(customers, orders, products)
            self._report()
            quality_issues = self._validate(customers, orders)
        except PipelineError as e:
            log.error('pipeline failed: %s', e)
            self._errors.append(str(e))
            quality_issues = []
        except Exception as e:
            log.exception('pipeline crashed')
            self._errors.append(f'fatal: {e}')
            quality_issues = []

        metrics = self._collect_metrics(
            customers if 'customers' in locals() else [],
            orders if 'orders' in locals() else [],
            products if 'products' in locals() else [],
            returns if 'returns' in locals() else [],
        )
        AlertManager(
            self._config.alert_recipients,
            failure_threshold=self._config.alert_failure_threshold,
            error_threshold=self._config.alert_error_threshold,
            runtime_seconds=self._config.alert_runtime_seconds,
        ).check(metrics)

        run_id = hashlib.sha256(str(self._start_time).encode()).hexdigest()[:16]
        status = 'success' if not self._errors else 'partial'
        result = PipelineRunResult(
            run_id=run_id, status=status, metrics=metrics,
            quality_issues=quality_issues, errors=self._errors[:],
        )
        try:
            self._warehouse.record_run(result)
        except Exception as e:
            log.error('failed to record run: %s', e)
        self._warehouse.close()
        elapsed = time.time() - (self._start_time or time.time())
        log.info('pipeline complete in %.1fs (status=%s, processed=%d, failed=%d)',
                 elapsed, status, self._processed, self._failed)
        return result

    def _extract(self) -> Tuple[List[Customer], List[Dict[str, Any]],
                                List[Product], List[ReturnRecord]]:
        log.info('extracting sources')
        customers = CustomerCsvExtractor(self._config.customers_csv).extract()
        orders = OrdersApiExtractor(
            base_url=self._config.orders_api_url,
            api_key=self._config.orders_api_key,
            page_size=self._config.api_page_size,
            max_pages=self._config.api_max_pages,
            rate_limit_seconds=self._config.api_rate_limit_seconds,
            timeout_seconds=self._config.api_timeout_seconds,
            since=self._config.since,
            max_attempts=self._config.max_retry_attempts,
            backoff_base=self._config.retry_backoff_base,
            backoff_factor=self._config.retry_backoff_factor,
        ).extract()
        products = ProductDbExtractor(self._config.products_db).extract()
        returns = ReturnsJsonExtractor(self._config.returns_json).extract()
        return customers, orders, products, returns

    def _transform(self, raw_orders: Sequence[Dict[str, Any]],
                   products: Sequence[Product],
                   returns: Sequence[ReturnRecord]) -> Tuple[List[Order], int]:
        log.info('transforming orders')
        products_by_id = {p.product_id: p for p in products}
        returns_by_order: Dict[str, List[ReturnRecord]] = defaultdict(list)
        for r in returns:
            returns_by_order[r.order_id].append(r)
        transformer = OrderTransformer(products_by_id, dict(returns_by_order))
        orders, failed = transformer.transform(raw_orders)
        log.info('transformed %d orders (%d failed)', len(orders), failed)
        return orders, failed

    def _enrich_customers(self, customers: Sequence[Customer],
                          orders: Sequence[Order]) -> None:
        log.info('enriching customers')
        enricher = CustomerEnricher(orders)
        for customer in customers:
            enricher.enrich(customer)

    def _load(self, customers: Sequence[Customer],
              orders: Sequence[Order], products: Sequence[Product]) -> None:
        log.info('loading into warehouse')
        self._warehouse.init_schema()
        loader = WarehouseLoader(self._warehouse, self._config.chunk_size)
        loader.load_customers(customers)
        loader.load_products(products)
        products_by_id = {p.product_id: p for p in products}
        returns_by_order: Dict[str, List[ReturnRecord]] = {}
        transformer = OrderTransformer(products_by_id, returns_by_order)
        loader.load_orders(orders, transformer)

    def _report(self) -> None:
        log.info('generating reports')
        ReportSuite.write_all(ReportSuite.default(), self._warehouse,
                              self._config.reports_dir)

    def _validate(self, customers: Sequence[Customer],
                  orders: Sequence[Order]) -> List[str]:
        log.info('running quality checks')
        checker = QualityChecker()
        issues = checker.run(self._warehouse, customers, orders)
        checker.write_report(issues, self._config.reports_dir / 'quality.txt')
        if issues:
            for issue in issues[:10]:
                self._errors.append(f'data quality: {issue}')
        return issues

    def _collect_metrics(self, customers: Sequence[Customer],
                         orders: Sequence[Order],
                         products: Sequence[Product],
                         returns: Sequence[ReturnRecord]) -> PipelineMetrics:
        runtime = time.time() - (self._start_time or time.time())
        return MetricsCollector(self._warehouse).collect(
            customers, orders, products, returns,
            self._processed, self._failed, len(self._errors), runtime,
        )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv: Optional[Sequence[str]] = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    setup_logging(verbose='--verbose' in argv or '-v' in argv)
    try:
        config = PipelineConfig.from_env()
    except (TypeError, ValueError) as e:
        log.error('invalid configuration: %s', e)
        return 2
    pipeline = Pipeline(config)
    try:
        result = pipeline.run()
    except KeyboardInterrupt:
        log.warning('interrupted')
        return 130
    return 0 if result.status == 'success' else 1


if __name__ == '__main__':
    sys.exit(main())
