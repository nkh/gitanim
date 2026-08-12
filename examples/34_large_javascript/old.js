import React from 'react';
import PropTypes from 'prop-types';

/**
 * DataGrid: a class-based table component that loads paginated rows
 * from an API endpoint, supports sorting, filtering, and row selection.
 * Uses lifecycle methods for data fetching and DOM measurements.
 */
class DataGrid extends React.Component {
  constructor(props) {
    super(props);
    this.state = {
      rows: [],
      totalCount: 0,
      loading: false,
      error: null,
      page: 0,
      pageSize: props.pageSize || 25,
      sortBy: props.defaultSortBy || null,
      sortDir: 'asc',
      filter: '',
      selectedRowIds: new Set(),
      expandedRowIds: new Set(),
      containerWidth: 0,
      lastUpdated: null,
    };
    this.containerRef = React.createRef();
    this.fetchPromise = null;
    this.pollTimer = null;
    this.resizeObserver = null;
  }

  componentDidMount() {
    this.loadRows();
    if (this.props.pollInterval) {
      this.pollTimer = setInterval(
        () => this.loadRows(true),
        this.props.pollInterval,
      );
    }
    this.measureContainer();
    window.addEventListener('resize', this.handleResize);
    if (typeof ResizeObserver !== 'undefined') {
      this.resizeObserver = new ResizeObserver(this.handleResize);
      if (this.containerRef.current) {
        this.resizeObserver.observe(this.containerRef.current);
      }
    }
  }

  componentDidUpdate(prevProps, prevState) {
    if (
      prevState.page !== this.state.page ||
      prevState.pageSize !== this.state.pageSize ||
      prevState.sortBy !== this.state.sortBy ||
      prevState.sortDir !== this.state.sortDir ||
      prevState.filter !== this.state.filter
    ) {
      this.loadRows();
    }
    if (
      prevProps.endpoint !== this.props.endpoint ||
      prevProps.apiKey !== this.props.apiKey
    ) {
      this.setState({ page: 0, selectedRowIds: new Set() }, () => {
        this.loadRows();
      });
    }
  }

  componentWillUnmount() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    window.removeEventListener('resize', this.handleResize);
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
    if (this.fetchPromise) {
      this.fetchPromise.cancelled = true;
    }
  }

  handleResize = () => {
    this.measureContainer();
  };

  measureContainer() {
    if (this.containerRef.current) {
      const width = this.containerRef.current.clientWidth;
      this.setState({ containerWidth: width });
    }
  }

  buildQuery() {
    const { page, pageSize, sortBy, sortDir, filter } = this.state;
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
  }

  loadRows(silent) {
    if (!silent) {
      this.setState({ loading: true, error: null });
    }
    const url = `${this.props.endpoint}?${this.buildQuery()}`;
    const promise = fetch(url, {
      headers: { 'X-Api-Key': this.props.apiKey || '' },
    }).then((res) => {
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      return res.json();
    });
    promise.cancelled = false;
    this.fetchPromise = promise;
    promise
      .then((data) => {
        if (promise.cancelled) {
          return;
        }
        this.setState({
          rows: data.rows || [],
          totalCount: data.total || 0,
          loading: false,
          lastUpdated: new Date(),
        });
      })
      .catch((err) => {
        if (promise.cancelled) {
          return;
        }
        this.setState({ loading: false, error: err.message });
      });
  }

  handleSort = (column) => {
    const { sortBy, sortDir } = this.state;
    if (sortBy === column) {
      this.setState({ sortDir: sortDir === 'asc' ? 'desc' : 'asc' });
    } else {
      this.setState({ sortBy: column, sortDir: 'asc', page: 0 });
    }
  };

  handleFilterChange = (event) => {
    const value = event.target.value;
    if (this.filterTimer) {
      clearTimeout(this.filterTimer);
    }
    this.filterTimer = setTimeout(() => {
      this.setState({ filter: value, page: 0 });
    }, 300);
  };

  handleSelect = (rowId) => {
    this.setState((prevState) => {
      const selected = new Set(prevState.selectedRowIds);
      if (selected.has(rowId)) {
        selected.delete(rowId);
      } else {
        selected.add(rowId);
      }
      return { selectedRowIds: selected };
    });
  };

  handleExpand = (rowId) => {
    this.setState((prevState) => {
      const expanded = new Set(prevState.expandedRowIds);
      if (expanded.has(rowId)) {
        expanded.delete(rowId);
      } else {
        expanded.add(rowId);
      }
      return { expandedRowIds: expanded };
    });
  };

  handleSelectAll = () => {
    this.setState((prevState) => {
      if (prevState.selectedRowIds.size === prevState.rows.length) {
        return { selectedRowIds: new Set() };
      }
      return {
        selectedRowIds: new Set(prevState.rows.map((r) => r.id)),
      };
    });
  };

  goToPage = (newPage) => {
    const maxPage = Math.max(
      0,
      Math.ceil(this.state.totalCount / this.state.pageSize) - 1,
    );
    this.setState({ page: Math.min(Math.max(0, newPage), maxPage) });
  };

  renderHeader() {
    const { columns } = this.props;
    const { sortBy, sortDir, selectedRowIds, rows } = this.state;
    const allSelected = rows.length > 0 && selectedRowIds.size === rows.length;
    return (
      <thead>
        <tr>
          <th className="datagrid-checkbox-cell">
            <input
              type="checkbox"
              checked={allSelected}
              onChange={this.handleSelectAll}
            />
          </th>
          {columns.map((col) => (
            <th
              key={col.key}
              onClick={() => this.handleSort(col.key)}
              className={sortBy === col.key ? `sorted-${sortDir}` : ''}
            >
              {col.label}
              {sortBy === col.key ? (sortDir === 'asc' ? ' ▲' : ' ▼') : ''}
            </th>
          ))}
          <th>Actions</th>
        </tr>
      </thead>
    );
  }

  renderRow(row) {
    const { columns, renderExpanded } = this.props;
    const { selectedRowIds, expandedRowIds } = this.state;
    const isSelected = selectedRowIds.has(row.id);
    const isExpanded = expandedRowIds.has(row.id);
    return (
      <React.Fragment key={row.id}>
        <tr className={isSelected ? 'selected' : ''}>
          <td>
            <input
              type="checkbox"
              checked={isSelected}
              onChange={() => this.handleSelect(row.id)}
            />
          </td>
          {columns.map((col) => (
            <td key={col.key}>{col.render ? col.render(row) : row[col.key]}</td>
          ))}
          <td>
            <button onClick={() => this.handleExpand(row.id)}>
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
  }

  renderToolbar() {
    const { filter, loading, lastUpdated, totalCount, page, pageSize } = this.state;
    return (
      <div className="datagrid-toolbar">
        <input
          type="text"
          placeholder="Filter..."
          defaultValue={filter}
          onChange={this.handleFilterChange}
        />
        <span className="datagrid-info">
          {loading ? 'Loading...' : `${totalCount} records`}
        </span>
        {lastUpdated && (
          <span className="datagrid-updated">
            Updated {lastUpdated.toLocaleTimeString()}
          </span>
        )}
        <button
          onClick={() => this.goToPage(page - 1)}
          disabled={page === 0}
        >
          Prev
        </button>
        <span>Page {page + 1}</span>
        <button
          onClick={() => this.goToPage(page + 1)}
          disabled={(page + 1) * pageSize >= totalCount}
        >
          Next
        </button>
        <button onClick={() => this.loadRows()}>Refresh</button>
      </div>
    );
  }

  render() {
    const { rows, loading, error, containerWidth } = this.state;
    const compact = containerWidth > 0 && containerWidth < 600;
    return (
      <div className={`datagrid ${compact ? 'compact' : ''}`} ref={this.containerRef}>
        {this.renderToolbar()}
        {error && <div className="datagrid-error">{error}</div>}
        <table>
          {this.renderHeader()}
          <tbody>
            {loading && rows.length === 0 ? (
              <tr>
                <td colSpan={this.props.columns.length + 2}>Loading...</td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={this.props.columns.length + 2}>No data</td>
              </tr>
            ) : (
              rows.map((row) => this.renderRow(row))
            )}
          </tbody>
        </table>
      </div>
    );
  }
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
