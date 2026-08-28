#!/usr/bin/env python3
"""Data pipeline script — monolithic implementation.

Reads customer, order, and product data from multiple sources, joins and
aggregates them, applies business rules, writes denormalized output to a
data warehouse, and generates a summary report. Everything is inlined in
a single file with no classes, no config, no logging.
"""

import csv
import json
import os
import sys
import time
import sqlite3
import hashlib
import datetime
import statistics
import smtplib
from email.mime.text import MIMEText
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError


# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

PROCESSED_RECORDS = 0
FAILED_RECORDS = 0
ERROR_LOG = []
START_TIME = None


# ---------------------------------------------------------------------------
# Database helpers (raw sqlite3, no ORM, no pooling)
# ---------------------------------------------------------------------------

def open_db(path):
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL')
    return conn


def close_db(conn):
    try:
        conn.commit()
        conn.close()
    except Exception as e:
        ERROR_LOG.append(f'close_db: {e}')


def init_warehouse_schema(conn):
    conn.executescript('''
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
    ''')


# ---------------------------------------------------------------------------
# Source: customers (CSV file)
# ---------------------------------------------------------------------------

def load_customers_from_csv(path):
    customers = []
    if not os.path.exists(path):
        ERROR_LOG.append(f'customers CSV not found: {path}')
        return customers
    try:
        with open(path, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    customer = {
                        'customer_id': row['customer_id'].strip(),
                        'name': row['name'].strip(),
                        'email': row['email'].strip().lower(),
                        'country': row['country'].strip().upper(),
                        'signup_date': row['signup_date'].strip(),
                        'segment': row.get('segment', 'standard').strip().lower(),
                    }
                    if not customer['customer_id'] or not customer['email']:
                        ERROR_LOG.append(f'skipping customer row: missing required field: {row}')
                        continue
                    customers.append(customer)
                except KeyError as e:
                    ERROR_LOG.append(f'customer row missing column {e}: {row}')
    except Exception as e:
        ERROR_LOG.append(f'failed to read customers CSV: {e}')
    return customers


# ---------------------------------------------------------------------------
# Source: orders (JSON via HTTP API with pagination)
# ---------------------------------------------------------------------------

def load_orders_from_api(base_url, api_key, since=None):
    all_orders = []
    page = 1
    per_page = 100
    while True:
        url = f'{base_url}?page={page}&per_page={per_page}'
        if since:
            url += f'&since={since}'
        req = Request(url, headers={
            'Authorization': f'Bearer {api_key}',
            'Accept': 'application/json',
        })
        try:
            with urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode('utf-8'))
        except HTTPError as e:
            ERROR_LOG.append(f'orders API HTTP error page {page}: {e}')
            break
        except URLError as e:
            ERROR_LOG.append(f'orders API URL error page {page}: {e}')
            break
        except Exception as e:
            ERROR_LOG.append(f'orders API error page {page}: {e}')
            break
        page_orders = data.get('orders', [])
        if not page_orders:
            break
        all_orders.extend(page_orders)
        if len(page_orders) < per_page:
            break
        page += 1
        if page > 1000:
            ERROR_LOG.append('orders API: exceeded 1000 pages, aborting pagination')
            break
        time.sleep(0.1)  # be nice to the API
    return all_orders


# ---------------------------------------------------------------------------
# Source: products (sqlite3)
# ---------------------------------------------------------------------------

def load_products_from_db(path):
    products = []
    if not os.path.exists(path):
        ERROR_LOG.append(f'products DB not found: {path}')
        return products
    try:
        conn = open_db(path)
        cur = conn.execute('SELECT * FROM products')
        for row in cur.fetchall():
            products.append(dict(row))
        close_db(conn)
    except Exception as e:
        ERROR_LOG.append(f'failed to read products DB: {e}')
    return products


# ---------------------------------------------------------------------------
# Source: returns (JSON file)
# ---------------------------------------------------------------------------

def load_returns_from_json(path):
    returns = []
    if not os.path.exists(path):
        return returns
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        returns = data.get('returns', [])
    except Exception as e:
        ERROR_LOG.append(f'failed to read returns JSON: {e}')
    return returns


# ---------------------------------------------------------------------------
# Transformations
# ---------------------------------------------------------------------------

def compute_customer_lifetime_value(customer, orders):
    total = 0.0
    order_count = 0
    last_order_date = None
    for order in orders:
        if order.get('customer_id') != customer['customer_id']:
            continue
        if order.get('status') in ('paid', 'shipped', 'delivered'):
            total += float(order.get('total', 0))
            order_count += 1
            d = order.get('order_date')
            if d and (last_order_date is None or d > last_order_date):
                last_order_date = d
    customer['lifetime_value'] = round(total, 2)
    customer['order_count'] = order_count
    customer['last_order_date'] = last_order_date
    return customer


def assign_customer_segment(customer):
    ltv = customer.get('lifetime_value', 0)
    order_count = customer.get('order_count', 0)
    if ltv > 5000 or order_count > 50:
        customer['segment'] = 'platinum'
    elif ltv > 1000 or order_count > 10:
        customer['segment'] = 'gold'
    elif ltv > 100 or order_count > 0:
        customer['segment'] = 'silver'
    else:
        customer['segment'] = 'bronze'
    return customer


def normalize_order(order, products_by_id, returns_by_order):
    try:
        subtotal = float(order.get('subtotal', 0))
        discount = float(order.get('discount_amount', 0))
        tax = float(order.get('tax_amount', 0))
        shipping = float(order.get('shipping_amount', 0))
        total = float(order.get('total', subtotal - discount + tax + shipping))
    except (ValueError, TypeError) as e:
        ERROR_LOG.append(f'bad order totals for {order.get("id")}: {e}')
        return None

    items = order.get('line_items', [])
    item_count = 0
    for item in items:
        try:
            item_count += int(item.get('quantity', 0))
        except (ValueError, TypeError):
            pass

    returns = returns_by_order.get(order.get('id'), [])
    returned_amount = sum(float(r.get('refund_amount', 0)) for r in returns)

    return {
        'order_id': str(order.get('id')),
        'customer_id': str(order.get('customer_id')),
        'order_date': order.get('order_date') or order.get('created_at'),
        'status': order.get('status', 'unknown'),
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'shipping': shipping,
        'total': total,
        'item_count': item_count,
        'payment_method': order.get('payment_method', 'unknown'),
        'channel': order.get('channel', 'web'),
        'returned_amount': returned_amount,
        'line_items': items,
    }


def enrich_order_items(order, products_by_id):
    enriched = []
    for item in order.get('line_items', []):
        product_id = str(item.get('product_id'))
        product = products_by_id.get(product_id, {})
        enriched.append({
            'order_id': order['order_id'],
            'product_id': product_id,
            'quantity': int(item.get('quantity', 0)),
            'unit_price': float(item.get('unit_price', product.get('unit_price', 0))),
            'total_price': float(item.get('total_price', 0)),
            'category': product.get('category', 'unknown'),
        })
    return enriched


def hash_pii(value):
    if not value:
        return ''
    return hashlib.sha256(str(value).encode('utf-8')).hexdigest()[:16]


def deduplicate_orders(orders):
    seen = set()
    deduped = []
    for order in orders:
        oid = order.get('order_id')
        if oid in seen:
            continue
        seen.add(oid)
        deduped.append(order)
    return deduped


def filter_invalid_orders(orders):
    valid = []
    for order in orders:
        if not order:
            continue
        if not order.get('order_id') or not order.get('customer_id'):
            ERROR_LOG.append(f'skipping order with missing id: {order}')
            continue
        if not order.get('order_date'):
            ERROR_LOG.append(f'skipping order without date: {order.get("order_id")}')
            continue
        valid.append(order)
    return valid


# ---------------------------------------------------------------------------
# Loading into warehouse
# ---------------------------------------------------------------------------

def upsert_customer(conn, customer):
    conn.execute('''
        INSERT INTO dim_customers
        (customer_id, name, email, country, signup_date, segment,
         lifetime_value, order_count, last_order_date, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(customer_id) DO UPDATE SET
            name=excluded.name,
            email=excluded.email,
            country=excluded.country,
            signup_date=excluded.signup_date,
            segment=excluded.segment,
            lifetime_value=excluded.lifetime_value,
            order_count=excluded.order_count,
            last_order_date=excluded.last_order_date,
            updated_at=excluded.updated_at
    ''', (
        customer['customer_id'],
        customer['name'],
        hash_pii(customer['email']),
        customer['country'],
        customer['signup_date'],
        customer['segment'],
        customer.get('lifetime_value', 0),
        customer.get('order_count', 0),
        customer.get('last_order_date'),
        datetime.datetime.utcnow().isoformat(),
    ))


def upsert_product(conn, product):
    conn.execute('''
        INSERT INTO dim_products
        (product_id, sku, name, category, unit_price, cost,
         inventory_count, discontinued, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(product_id) DO UPDATE SET
            sku=excluded.sku,
            name=excluded.name,
            category=excluded.category,
            unit_price=excluded.unit_price,
            cost=excluded.cost,
            inventory_count=excluded.inventory_count,
            discontinued=excluded.discontinued,
            updated_at=excluded.updated_at
    ''', (
        str(product.get('product_id') or product.get('id')),
        product.get('sku'),
        product.get('name'),
        product.get('category'),
        float(product.get('unit_price', 0)),
        float(product.get('cost', 0)),
        int(product.get('inventory_count', 0)),
        1 if product.get('discontinued') else 0,
        datetime.datetime.utcnow().isoformat(),
    ))


def insert_order(conn, order):
    conn.execute('''
        INSERT OR REPLACE INTO fact_orders
        (order_id, customer_id, order_date, status, subtotal, discount,
         tax, shipping, total, item_count, payment_method, channel, inserted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        order['order_id'], order['customer_id'], order['order_date'],
        order['status'], order['subtotal'], order['discount'],
        order['tax'], order['shipping'], order['total'],
        order['item_count'], order['payment_method'], order['channel'],
        datetime.datetime.utcnow().isoformat(),
    ))


def insert_order_items(conn, items):
    conn.executemany('''
        INSERT INTO fact_order_items
        (order_id, product_id, quantity, unit_price, total_price, category)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', [(
        item['order_id'], item['product_id'], item['quantity'],
        item['unit_price'], item['total_price'], item['category'],
    ) for item in items])


# ---------------------------------------------------------------------------
# Reporting / aggregation
# ---------------------------------------------------------------------------

def generate_revenue_report(conn, output_path):
    cur = conn.execute('''
        SELECT
            strftime('%Y-%m', order_date) AS month,
            COUNT(*) AS order_count,
            SUM(subtotal) AS subtotal,
            SUM(discount) AS discount,
            SUM(tax) AS tax,
            SUM(shipping) AS shipping,
            SUM(total) AS total
        FROM fact_orders
        GROUP BY month
        ORDER BY month
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['month', 'orders', 'subtotal', 'discount', 'tax',
                         'shipping', 'total'])
        for row in rows:
            writer.writerow([row['month'], row['order_count'], row['subtotal'],
                             row['discount'], row['tax'], row['shipping'],
                             row['total']])


def generate_segment_report(conn, output_path):
    cur = conn.execute('''
        SELECT segment, COUNT(*) AS customer_count,
               AVG(lifetime_value) AS avg_ltv,
               SUM(lifetime_value) AS total_ltv
        FROM dim_customers
        GROUP BY segment
        ORDER BY total_ltv DESC
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['segment', 'customers', 'avg_ltv', 'total_ltv'])
        for row in rows:
            writer.writerow([row['segment'], row['customer_count'],
                             row['avg_ltv'], row['total_ltv']])


def generate_product_report(conn, output_path):
    cur = conn.execute('''
        SELECT p.product_id, p.name, p.category,
               SUM(oi.quantity) AS units_sold,
               SUM(oi.total_price) AS revenue
        FROM dim_products p
        LEFT JOIN fact_order_items oi ON oi.product_id = p.product_id
        GROUP BY p.product_id
        ORDER BY revenue DESC
        LIMIT 100
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['product_id', 'name', 'category', 'units_sold', 'revenue'])
        for row in rows:
            writer.writerow([row['product_id'], row['name'], row['category'],
                             row['units_sold'] or 0, row['revenue'] or 0])


def generate_return_report(conn, output_path):
    cur = conn.execute('''
        SELECT strftime('%Y-%m', order_date) AS month,
               COUNT(DISTINCT o.order_id) AS returned_orders,
               SUM(o.total) AS gross_revenue
        FROM fact_orders o
        WHERE o.order_id IN (SELECT DISTINCT order_id FROM fact_order_items)
        GROUP BY month
        ORDER BY month
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['month', 'returned_orders', 'gross_revenue'])
        for row in rows:
            writer.writerow([row['month'], row['returned_orders'],
                             row['gross_revenue']])


def generate_cohort_report(conn, output_path):
    cur = conn.execute('''
        SELECT
            c.signup_date AS signup_month,
            strftime('%Y-%m', o.order_date) AS order_month,
            COUNT(DISTINCT o.order_id) AS orders
        FROM dim_customers c
        LEFT JOIN fact_orders o ON o.customer_id = c.customer_id
        WHERE c.signup_date IS NOT NULL
        GROUP BY signup_month, order_month
        ORDER BY signup_month, order_month
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['signup_month', 'order_month', 'orders'])
        for row in rows:
            writer.writerow([row['signup_month'], row['order_month'],
                             row['orders']])


def generate_funnel_report(conn, output_path):
    cur = conn.execute('''
        SELECT status, COUNT(*) AS n, SUM(total) AS revenue
        FROM fact_orders
        GROUP BY status
        ORDER BY revenue DESC
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['status', 'count', 'revenue'])
        for row in rows:
            writer.writerow([row['status'], row['n'], row['revenue']])


def generate_geo_report(conn, output_path):
    cur = conn.execute('''
        SELECT c.country, COUNT(DISTINCT o.order_id) AS orders,
               SUM(o.total) AS revenue, COUNT(DISTINCT c.customer_id) AS customers
        FROM dim_customers c
        LEFT JOIN fact_orders o ON o.customer_id = c.customer_id
        GROUP BY c.country
        ORDER BY revenue DESC
    ''')
    rows = cur.fetchall()
    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['country', 'orders', 'revenue', 'customers'])
        for row in rows:
            writer.writerow([row['country'], row['orders'], row['revenue'],
                             row['customers']])


# ---------------------------------------------------------------------------
# Data quality checks
# ---------------------------------------------------------------------------

def check_referential_integrity(conn):
    issues = []
    cur = conn.execute('''
        SELECT COUNT(*) AS n FROM fact_orders o
        LEFT JOIN dim_customers c ON c.customer_id = o.customer_id
        WHERE c.customer_id IS NULL
    ''')
    orphan_orders = cur.fetchone()['n']
    if orphan_orders > 0:
        issues.append(f'{orphan_orders} orders reference unknown customers')

    cur = conn.execute('''
        SELECT COUNT(*) AS n FROM fact_order_items oi
        LEFT JOIN dim_products p ON p.product_id = oi.product_id
        WHERE p.product_id IS NULL
    ''')
    orphan_items = cur.fetchone()['n']
    if orphan_items > 0:
        issues.append(f'{orphan_items} order items reference unknown products')

    cur = conn.execute('''
        SELECT COUNT(*) AS n FROM fact_orders WHERE total < 0
    ''')
    negative_totals = cur.fetchone()['n']
    if negative_totals > 0:
        issues.append(f'{negative_totals} orders have negative totals')

    cur = conn.execute('''
        SELECT COUNT(*) AS n FROM fact_orders WHERE order_date IS NULL OR order_date = ''
    ''')
    missing_dates = cur.fetchone()['n']
    if missing_dates > 0:
        issues.append(f'{missing_dates} orders have missing dates')

    cur = conn.execute('''
        SELECT COUNT(*) AS n FROM dim_customers WHERE email IS NULL OR email = ''
    ''')
    missing_emails = cur.fetchone()['n']
    if missing_emails > 0:
        issues.append(f'{missing_emails} customers have missing emails')

    return issues


def validate_order_totals(orders):
    issues = []
    for order in orders:
        expected_total = (order.get('subtotal', 0) - order.get('discount', 0)
                          + order.get('tax', 0) + order.get('shipping', 0))
        actual_total = order.get('total', 0)
        if abs(expected_total - actual_total) > 0.01:
            issues.append(f"order {order.get('order_id')} total mismatch: "
                          f"expected {expected_total:.2f}, got {actual_total:.2f}")
    return issues


def check_customer_segments(customers):
    issues = []
    valid_segments = {'platinum', 'gold', 'silver', 'bronze', 'standard'}
    for c in customers:
        seg = c.get('segment')
        if seg not in valid_segments:
            issues.append(f"customer {c.get('customer_id')} has invalid segment: {seg}")
    return issues


def check_date_ranges(orders):
    issues = []
    today = datetime.date.today().isoformat()
    one_year_ago = (datetime.date.today() - datetime.timedelta(days=365)).isoformat()
    for order in orders:
        d = order.get('order_date')
        if not d:
            continue
        if d > today:
            issues.append(f"order {order.get('order_id')} has future date: {d}")
        elif d < one_year_ago:
            issues.append(f"order {order.get('order_id')} has very old date: {d}")
    return issues


def run_all_quality_checks(conn, customers, orders):
    all_issues = []
    all_issues.extend(check_referential_integrity(conn))
    all_issues.extend(validate_order_totals(orders))
    all_issues.extend(check_customer_segments(customers))
    all_issues.extend(check_date_ranges(orders))
    return all_issues


def write_quality_report(issues, output_path):
    with open(output_path, 'w', encoding='utf-8') as f:
        if not issues:
            f.write('No data quality issues found.\n')
            return
        f.write(f'{len(issues)} data quality issues found:\n\n')
        for i, issue in enumerate(issues, 1):
            f.write(f'{i}. {issue}\n')


# ---------------------------------------------------------------------------
# Retry helpers
# ---------------------------------------------------------------------------

def retry(fn, args=(), kwargs=None, attempts=3, delay=1.0, backoff=2.0):
    kwargs = kwargs or {}
    last_exc = None
    current_delay = delay
    for attempt in range(1, attempts + 1):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            last_exc = e
            ERROR_LOG.append(f'retry attempt {attempt}/{attempts} for {fn.__name__}: {e}')
            if attempt < attempts:
                time.sleep(current_delay)
                current_delay *= backoff
    raise last_exc


def chunked(iterable, size):
    items = list(iterable)
    for i in range(0, len(items), size):
        yield items[i:i + size]


def write_run_summary(run_id, metrics, issues, output_path):
    """Write a human-readable summary of the pipeline run."""
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('Pipeline Run Summary\n')
        f.write('=' * 60 + '\n\n')
        f.write(f'Run ID:          {run_id}\n')
        f.write(f'Started:         {datetime.datetime.utcfromtimestamp(START_TIME).isoformat()}\n')
        f.write(f'Finished:        {datetime.datetime.utcnow().isoformat()}\n')
        f.write(f'Duration:        {metrics.get("runtime_seconds", 0):.1f} seconds\n\n')
        f.write(f'Records processed: {metrics.get("processed_records", 0)}\n')
        f.write(f'Records failed:    {metrics.get("failed_records", 0)}\n')
        f.write(f'Errors logged:     {metrics.get("error_count", 0)}\n')
        f.write(f'Data quality issues: {len(issues)}\n\n')
        f.write('Counts:\n')
        f.write(f'  Customers:    {metrics.get("customer_count", 0)}\n')
        f.write(f'  Orders:       {metrics.get("order_count", 0)}\n')
        f.write(f'  Products:     {metrics.get("product_count", 0)}\n')
        f.write(f'  Returns:      {metrics.get("return_count", 0)}\n\n')
        if 'avg_order_value' in metrics:
            f.write('Order value:\n')
            f.write(f'  Average:      ${metrics.get("avg_order_value", 0):.2f}\n')
            f.write(f'  Median:       ${metrics.get("median_order_value", 0):.2f}\n')
            f.write(f'  Min:          ${metrics.get("min_order_value", 0):.2f}\n')
            f.write(f'  Max:          ${metrics.get("max_order_value", 0):.2f}\n')
            f.write(f'  Total:        ${metrics.get("total_revenue", 0):.2f}\n\n')
        if 'avg_ltv' in metrics:
            f.write('Customer LTV:\n')
            f.write(f'  Average:      ${metrics.get("avg_ltv", 0):.2f}\n')
            f.write(f'  Median:       ${metrics.get("median_ltv", 0):.2f}\n')
            f.write(f'  Max:          ${metrics.get("max_ltv", 0):.2f}\n')
            f.write(f'  Total:        ${metrics.get("total_ltv", 0):.2f}\n\n')
        if issues:
            f.write('Data quality issues (first 20):\n')
            for issue in issues[:20]:
                f.write(f'  - {issue}\n')
        if ERROR_LOG:
            f.write('\nErrors (first 20):\n')
            for err in ERROR_LOG[:20]:
                f.write(f'  - {err}\n')


# ---------------------------------------------------------------------------
# Metrics / monitoring
# ---------------------------------------------------------------------------

def collect_metrics(conn, customers, orders, products, returns):
    metrics = {}
    metrics['customer_count'] = len(customers)
    metrics['order_count'] = len(orders)
    metrics['product_count'] = len(products)
    metrics['return_count'] = len(returns)
    metrics['processed_records'] = PROCESSED_RECORDS
    metrics['failed_records'] = FAILED_RECORDS
    metrics['error_count'] = len(ERROR_LOG)
    metrics['runtime_seconds'] = time.time() - START_TIME if START_TIME else 0

    cur = conn.execute('SELECT COUNT(*) AS n FROM dim_customers')
    metrics['warehouse_customers'] = cur.fetchone()['n']
    cur = conn.execute('SELECT COUNT(*) AS n FROM dim_products')
    metrics['warehouse_products'] = cur.fetchone()['n']
    cur = conn.execute('SELECT COUNT(*) AS n FROM fact_orders')
    metrics['warehouse_orders'] = cur.fetchone()['n']
    cur = conn.execute('SELECT COUNT(*) AS n FROM fact_order_items')
    metrics['warehouse_order_items'] = cur.fetchone()['n']

    if orders:
        totals = [o.get('total', 0) for o in orders]
        metrics['avg_order_value'] = statistics.mean(totals)
        metrics['median_order_value'] = statistics.median(totals)
        metrics['max_order_value'] = max(totals)
        metrics['min_order_value'] = min(totals)
        metrics['total_revenue'] = sum(totals)

    if customers:
        ltvs = [c.get('lifetime_value', 0) for c in customers]
        metrics['avg_ltv'] = statistics.mean(ltvs)
        metrics['median_ltv'] = statistics.median(ltvs)
        metrics['max_ltv'] = max(ltvs)
        metrics['total_ltv'] = sum(ltvs)

    return metrics


def emit_metrics(metrics, statsd_host=None, statsd_port=8125):
    # In a real pipeline this would send to statsd. We just print here.
    for key, value in metrics.items():
        print(f'metric {key} = {value}')


# ---------------------------------------------------------------------------
# Alerts / notifications
# ---------------------------------------------------------------------------

def send_alert_email(subject, body, recipients, smtp_host='localhost', smtp_port=25):
    if not recipients:
        return
    msg = MIMEText(body)
    msg['Subject'] = subject
    msg['From'] = 'pipeline@example.com'
    msg['To'] = ', '.join(recipients)
    try:
        with smtplib.SMTP(smtp_host, smtp_port) as s:
            s.send_message(msg)
    except Exception as e:
        ERROR_LOG.append(f'failed to send alert email: {e}')


def check_alerts(metrics, alert_recipients):
    if metrics.get('failed_records', 0) > 100:
        send_alert_email(
            'Pipeline alert: high failure rate',
            f"{metrics['failed_records']} failed records in last run",
            alert_recipients,
        )
    if metrics.get('error_count', 0) > 50:
        send_alert_email(
            'Pipeline alert: high error count',
            f"{metrics['error_count']} errors logged in last run",
            alert_recipients,
        )
    if metrics.get('runtime_seconds', 0) > 3600:
        send_alert_email(
            'Pipeline alert: long runtime',
            f"Pipeline took {metrics['runtime_seconds']:.0f} seconds to complete",
            alert_recipients,
        )


# ---------------------------------------------------------------------------
# Pipeline orchestration
# ---------------------------------------------------------------------------

def run_pipeline():
    global START_TIME, PROCESSED_RECORDS, FAILED_RECORDS
    START_TIME = time.time()

    # Read config from environment.
    customers_csv = os.environ.get('CUSTOMERS_CSV', 'data/customers.csv')
    orders_api_url = os.environ.get('ORDERS_API_URL', 'http://localhost:4000/api/orders')
    orders_api_key = os.environ.get('ORDERS_API_KEY', '')
    products_db = os.environ.get('PRODUCTS_DB', 'data/products.db')
    returns_json = os.environ.get('RETURNS_JSON', 'data/returns.json')
    warehouse_path = os.environ.get('WAREHOUSE_DB', 'data/warehouse.db')
    reports_dir = os.environ.get('REPORTS_DIR', 'reports')
    since = os.environ.get('SINCE', None)
    alert_recipients = [r for r in os.environ.get('ALERT_RECIPIENTS', '').split(',') if r]

    os.makedirs(reports_dir, exist_ok=True)

    print(f'[{datetime.datetime.utcnow().isoformat()}] starting pipeline')

    # Extract.
    print('loading customers...')
    customers = load_customers_from_csv(customers_csv)
    print(f'  loaded {len(customers)} customers')

    print('loading orders...')
    orders = load_orders_from_api(orders_api_url, orders_api_key, since=since)
    print(f'  loaded {len(orders)} orders')

    print('loading products...')
    products = load_products_from_db(products_db)
    print(f'  loaded {len(products)} products')

    print('loading returns...')
    returns = load_returns_from_json(returns_json)
    print(f'  loaded {len(returns)} returns')

    # Build lookup tables.
    products_by_id = {str(p.get('product_id') or p.get('id')): p for p in products}
    returns_by_order = {}
    for r in returns:
        returns_by_order.setdefault(r.get('order_id'), []).append(r)

    # Validate & deduplicate.
    orders = filter_invalid_orders(orders)
    orders = deduplicate_orders(orders)

    # Normalize orders.
    print('normalizing orders...')
    normalized = []
    for order in orders:
        n = normalize_order(order, products_by_id, returns_by_order)
        if n is None:
            FAILED_RECORDS += 1
            continue
        normalized.append(n)
        PROCESSED_RECORDS += 1
    orders = normalized

    # Compute customer lifetime values & segments.
    print('enriching customers...')
    for customer in customers:
        compute_customer_lifetime_value(customer, orders)
        assign_customer_segment(customer)

    # Write to warehouse.
    print('writing to warehouse...')
    conn = open_db(warehouse_path)
    try:
        init_warehouse_schema(conn)
        for customer in customers:
            upsert_customer(conn, customer)
        for product in products:
            upsert_product(conn, product)
        all_items = []
        for order in orders:
            insert_order(conn, order)
            items = enrich_order_items(order, products_by_id)
            all_items.extend(items)
        if all_items:
            insert_order_items(conn, all_items)
        conn.commit()
    except Exception as e:
        ERROR_LOG.append(f'warehouse write failed: {e}')
        conn.rollback()
    close_db(conn)

    # Generate reports.
    print('generating reports...')
    conn = open_db(warehouse_path)
    try:
        generate_revenue_report(conn, os.path.join(reports_dir, 'revenue.csv'))
        generate_segment_report(conn, os.path.join(reports_dir, 'segments.csv'))
        generate_product_report(conn, os.path.join(reports_dir, 'top_products.csv'))
        generate_return_report(conn, os.path.join(reports_dir, 'returns.csv'))
        generate_cohort_report(conn, os.path.join(reports_dir, 'cohorts.csv'))
        generate_funnel_report(conn, os.path.join(reports_dir, 'funnel.csv'))
        generate_geo_report(conn, os.path.join(reports_dir, 'geo.csv'))
    except Exception as e:
        ERROR_LOG.append(f'report generation failed: {e}')
    close_db(conn)

    # Data quality checks.
    print('running data quality checks...')
    conn = open_db(warehouse_path)
    try:
        issues = run_all_quality_checks(conn, customers, orders)
        write_quality_report(issues, os.path.join(reports_dir, 'quality.txt'))
        if issues:
            for issue in issues[:10]:
                ERROR_LOG.append(f'data quality: {issue}')
    except Exception as e:
        ERROR_LOG.append(f'quality check failed: {e}')
    close_db(conn)

    # Collect & emit metrics.
    print('collecting metrics...')
    conn = open_db(warehouse_path)
    metrics = collect_metrics(conn, customers, orders, products, returns)
    close_db(conn)
    emit_metrics(metrics)

    # Record run in pipeline_runs.
    print('recording run...')
    conn = open_db(warehouse_path)
    run_id = hashlib.sha256(str(START_TIME).encode()).hexdigest()[:16]
    conn.execute('''
        INSERT INTO pipeline_runs
        (run_id, started_at, finished_at, status, processed, failed, errors)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (
        run_id,
        datetime.datetime.utcfromtimestamp(START_TIME).isoformat(),
        datetime.datetime.utcnow().isoformat(),
        'success' if not ERROR_LOG else 'partial',
        PROCESSED_RECORDS,
        FAILED_RECORDS,
        '\n'.join(ERROR_LOG[:100]),
    ))
    close_db(conn)

    # Check alerts.
    check_alerts(metrics, alert_recipients)

    elapsed = time.time() - START_TIME
    print(f'[{datetime.datetime.utcnow().isoformat()}] pipeline complete in {elapsed:.1f}s')
    print(f'  processed={PROCESSED_RECORDS}, failed={FAILED_RECORDS}, errors={len(ERROR_LOG)}')

    if ERROR_LOG:
        print('first 10 errors:')
        for err in ERROR_LOG[:10]:
            print(f'  - {err}')

    return 0 if not ERROR_LOG else 1


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main():
    try:
        rc = run_pipeline()
    except KeyboardInterrupt:
        print('interrupted')
        return 130
    except Exception as e:
        ERROR_LOG.append(f'fatal: {e}')
        print(f'fatal: {e}')
        return 1
    return rc


if __name__ == '__main__':
    sys.exit(main())
