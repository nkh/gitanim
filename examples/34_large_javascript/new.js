import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import PropTypes from 'prop-types';

/**
 * DataGrid: a function-based table component using React hooks.
 * Supports sorting, filtering, paginated server-side loading, polling,
 * row selection, row expansion, and responsive container measurement.
 */

const PAGE_SIZE_DEFAULT = 25;
const FILTER_DEBOUNCE_MS = 300;
const COMPACT_BREAKPOINT_PX = 600;

function useDebouncedValue(value, delayMs) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}

function useContainerWidth() {
  const ref = useRef(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return undefined;
    const measure = () => setWidth(el.clientWidth);
    measure();
    window.addEventListener('resize', measure);
    let observer;
    if (typeof ResizeObserver !== 'undefined') {
      observer = new ResizeObserver(measure);
      observer.observe(el);
    }
    return () => {
      window.removeEventListener('resize', measure);
      if (observer) observer.disconnect();
    };
  }, []);
  return [ref, width];
}

function useFetchRows({ endpoint, apiKey, page, pageSize, sortBy, sortDir, filter }) {
  const [rows, setRows] = useState([]);
  const [totalCount, setTotalCount] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);
  const cancelledRef = useRef(false);

  const queryString = useMemo(() => {
    const params = new URLSearchParams();
    params.set('offset', String(page * pageSize));
    params.set('limit', String(pageSize));
    if (sortBy) {
      params.set('sort', sortBy);
      params.set('dir', sortDir);
    }
    if (filter) {
      params.set('q', filter);
    }
    return params.toString();
  }, [page, pageSize, sortBy, sortDir, filter]);

  useEffect(() => {
    cancelledRef.current = false;
    setLoading(true);
    setError(null);
    const url = `${endpoint}?${queryString}`;
    const controller = new AbortController();
    fetch(url, {
      headers: { 'X-Api-Key': apiKey || '' },
      signal: controller.signal,
    })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (cancelledRef.current) return;
        setRows(data.rows || []);
        setTotalCount(data.total || 0);
        setLastUpdated(new Date());
        setLoading(false);
      })
      .catch((err) => {
        if (cancelledRef.current || err.name === 'AbortError') return;
        setError(err.message);
        setLoading(false);
      });
    return () => {
      cancelledRef.current = true;
      controller.abort();
    };
  }, [endpoint, apiKey, queryString]);

  const refresh = useCallback(() => {
    cancelledRef.current = false;
    setLoading(true);
    fetch(`${endpoint}?${queryString}`, {
      headers: { 'X-Api-Key': apiKey || '' },
    })
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => {
        if (cancelledRef.current) return;
        setRows(data.rows || []);
        setTotalCount(data.total || 0);
        setLastUpdated(new Date());
        setLoading(false);
      })
      .catch((err) => {
        if (cancelledRef.current) return;
        setError(err.message);
        setLoading(false);
      });
  }, [endpoint, apiKey, queryString]);

  return { rows, totalCount, loading, error, lastUpdated, refresh };
}

function usePolling(callback, intervalMs) {
  const savedCallback = useRef(callback);
  useEffect(() => { savedCallback.current = callback; }, [callback]);
  useEffect(() => {
    if (!intervalMs) return undefined;
    const id = setInterval(() => savedCallback.current(true), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
}

function DataGrid(props) {
  const {
    endpoint,
    apiKey,
    columns,
    pageSize = PAGE_SIZE_DEFAULT,
    defaultSortBy = null,
    pollInterval,
    renderExpanded,
  } = props;

  const [page, setPage] = useState(0);
  const [sortBy, setSortBy] = useState(defaultSortBy);
  const [sortDir, setSortDir] = useState('asc');
  const [filterInput, setFilterInput] = useState('');
  const filter = useDebouncedValue(filterInput, FILTER_DEBOUNCE_MS);
  const [selectedRowIds, setSelectedRowIds] = useState(() => new Set());
  const [expandedRowIds, setExpandedRowIds] = useState(() => new Set());

  const { rows, totalCount, loading, error, lastUpdated, refresh } = useFetchRows({
    endpoint, apiKey, page, pageSize, sortBy, sortDir, filter,
  });

  const [containerRef, containerWidth] = useContainerWidth();

  const silentRefresh = useCallback(() => { refresh(); }, [refresh]);
  usePolling(silentRefresh, pollInterval);

  useEffect(() => {
    // Reset pagination/selection when the data source changes.
    setPage(0);
    setSelectedRowIds(new Set());
  }, [endpoint, apiKey]);

  const handleSort = useCallback((columnKey) => {
    setSortBy((prevSort) => {
      if (prevSort === columnKey) {
        setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
        return prevSort;
      }
      setSortDir('asc');
      setPage(0);
      return columnKey;
    });
  }, []);

  const handleFilterChange = useCallback((event) => {
    setFilterInput(event.target.value);
    setPage(0);
  }, []);

  const handleSelect = useCallback((rowId) => {
    setSelectedRowIds((prev) => {
      const next = new Set(prev);
      if (next.has(rowId)) {
        next.delete(rowId);
      } else {
        next.add(rowId);
      }
      return next;
    });
  }, []);

  const handleExpand = useCallback((rowId) => {
    setExpandedRowIds((prev) => {
      const next = new Set(prev);
      if (next.has(rowId)) {
        next.delete(rowId);
      } else {
        next.add(rowId);
      }
      return next;
    });
  }, []);

  const handleSelectAll = useCallback(() => {
    setSelectedRowIds((prev) => {
      if (prev.size === rows.length) return new Set();
      return new Set(rows.map((r) => r.id));
    });
  }, [rows]);

  const maxPage = Math.max(0, Math.ceil(totalCount / pageSize) - 1);
  const goToPage = useCallback((newPage) => {
    setPage(Math.min(Math.max(0, newPage), maxPage));
  }, [maxPage]);

  const allSelected = rows.length > 0 && selectedRowIds.size === rows.length;
  const compact = containerWidth > 0 && containerWidth < COMPACT_BREAKPOINT_PX;

  const headerCells = useMemo(() => (
    columns.map((col) => (
      <th
        key={col.key}
        onClick={() => handleSort(col.key)}
        className={sortBy === col.key ? `sorted-${sortDir}` : ''}
      >
        {col.label}
        {sortBy === col.key ? (sortDir === 'asc' ? ' ▲' : ' ▼') : ''}
      </th>
    ))
  ), [columns, sortBy, sortDir, handleSort]);

  const bodyRows = useMemo(() => {
    if (loading && rows.length === 0) {
      return (
        <tr>
          <td colSpan={columns.length + 2}>Loading...</td>
        </tr>
      );
    }
    if (rows.length === 0) {
      return (
        <tr>
          <td colSpan={columns.length + 2}>No data</td>
        </tr>
      );
    }
    return rows.map((row) => {
      const isSelected = selectedRowIds.has(row.id);
      const isExpanded = expandedRowIds.has(row.id);
      return (
        <React.Fragment key={row.id}>
          <tr className={isSelected ? 'selected' : ''}>
            <td>
              <input
                type="checkbox"
                checked={isSelected}
                onChange={() => handleSelect(row.id)}
              />
            </td>
            {columns.map((col) => (
              <td key={col.key}>
                {col.render ? col.render(row) : row[col.key]}
              </td>
            ))}
            <td>
              <button onClick={() => handleExpand(row.id)}>
                {isExpanded ? 'Collapse' : 'Expand'}
              </button>
            </td>
          </tr>
          {isExpanded && renderExpanded && (
            <tr className="expanded-row">
              <td colSpan={columns.length + 2}>{renderExpanded(row)}</td>
            </tr>
          )}
        </React.Fragment>
      );
    });
  }, [rows, loading, columns, selectedRowIds, expandedRowIds, handleSelect, handleExpand, renderExpanded]);

  return (
    <div className={`datagrid ${compact ? 'compact' : ''}`} ref={containerRef}>
      <div className="datagrid-toolbar">
        <input
          type="text"
          placeholder="Filter..."
          value={filterInput}
          onChange={handleFilterChange}
        />
        <span className="datagrid-info">
          {loading ? 'Loading...' : `${totalCount} records`}
        </span>
        {lastUpdated && (
          <span className="datagrid-updated">
            Updated {lastUpdated.toLocaleTimeString()}
          </span>
        )}
        <button onClick={() => goToPage(page - 1)} disabled={page === 0}>
          Prev
        </button>
        <span>Page {page + 1}</span>
        <button
          onClick={() => goToPage(page + 1)}
          disabled={(page + 1) * pageSize >= totalCount}
        >
          Next
        </button>
        <button onClick={refresh}>Refresh</button>
      </div>
      {error && <div className="datagrid-error">{error}</div>}
      <table>
        <thead>
          <tr>
            <th className="datagrid-checkbox-cell">
              <input
                type="checkbox"
                checked={allSelected}
                onChange={handleSelectAll}
              />
            </th>
            {headerCells}
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>{bodyRows}</tbody>
      </table>
    </div>
  );
}

DataGrid.propTypes = {
  endpoint: PropTypes.string.isRequired,
  apiKey: PropTypes.string,
  columns: PropTypes.arrayOf(
    PropTypes.shape({
      key: PropTypes.string.isRequired,
      label: PropTypes.string.isRequired,
      render: PropTypes.func,
    }),
  ).isRequired,
  pageSize: PropTypes.number,
  defaultSortBy: PropTypes.string,
  pollInterval: PropTypes.number,
  renderExpanded: PropTypes.func,
};

export default DataGrid;
