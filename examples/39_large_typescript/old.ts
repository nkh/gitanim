// File uploader module — legacy implementation with `any` types and nested
// callbacks. Uploads are sequential with no error type narrowing.

type Callback = (err: any, result: any) => void;

const DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024; // 4 MiB
const DEFAULT_RETRIES = 3;
const DEFAULT_PARALLELISM = 1; // legacy: always sequential

interface UploaderOptions {
  endpoint?: any;
  chunkSize?: any;
  retries?: any;
  parallelism?: any;
  headers?: any;
  onProgress?: any;
  metadata?: any;
}

class FileUploader {
  endpoint: any;
  chunkSize: any;
  retries: any;
  parallelism: any;
  headers: any;
  onProgress: any;
  metadata: any;
  activeUploads: any;

  constructor(opts: UploaderOptions) {
    this.endpoint = opts.endpoint || '/api/uploads';
    this.chunkSize = opts.chunkSize || DEFAULT_CHUNK_SIZE;
    this.retries = opts.retries || DEFAULT_RETRIES;
    this.parallelism = opts.parallelism || DEFAULT_PARALLELISM;
    this.headers = opts.headers || {};
    this.onProgress = opts.onProgress || function () {};
    this.metadata = opts.metadata || {};
    this.activeUploads = {};
  }

  upload(file: any, cb: Callback) {
    const self = this;
    const uploadId = self._genId();
    self.activeUploads[uploadId] = { file: file, started: Date.now(), chunks: [] };

    self._initiateUpload(uploadId, file, function (err, sessionId) {
      if (err) {
        cb(err, null);
        return;
      }
      const chunks = self._splitChunks(file);
      self.activeUploads[uploadId].chunks = chunks;

      self._uploadChunks(uploadId, sessionId, chunks, 0, file, function (err2) {
        if (err2) {
          cb(err2, null);
          return;
        }
        self._finalizeUpload(sessionId, function (err3, result) {
          if (err3) {
            cb(err3, null);
            return;
          }
          delete self.activeUploads[uploadId];
          self.onProgress({ uploaded: file.size, total: file.size, done: true });
          cb(null, result);
        });
      });
    });
  }

  _initiateUpload(uploadId: any, file: any, cb: Callback) {
    const self = this;
    const body = JSON.stringify({
      upload_id: uploadId,
      filename: file.name,
      size: file.size,
      mime_type: file.type,
      metadata: self.metadata,
    });
    const xhr = new XMLHttpRequest();
    xhr.open('POST', self.endpoint + '/init');
    xhr.setRequestHeader('Content-Type', 'application/json');
    self._setHeaders(xhr);
    xhr.onload = function () {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          const parsed = JSON.parse(xhr.responseText);
          cb(null, parsed.session_id);
        } catch (e) {
          cb(e, null);
        }
      } else {
        cb(new Error('init failed: ' + xhr.status), null);
      }
    };
    xhr.onerror = function () {
      cb(new Error('init network error'), null);
    };
    xhr.send(body);
  }

  _uploadChunks(uploadId: any, sessionId: any, chunks: any, idx: any, file: any, cb: Callback) {
    const self = this;
    if (idx >= chunks.length) {
      cb(null);
      return;
    }
    const chunk = chunks[idx];
    self._uploadChunkWithRetry(sessionId, idx, chunk, self.retries, function (err, result) {
      if (err) {
        cb(err);
        return;
      }
      self.onProgress({
        uploaded: (idx + 1) * self.chunkSize,
        total: file.size,
        done: false,
      });
      self._uploadChunks(uploadId, sessionId, chunks, idx + 1, file, cb);
    });
  }

  _uploadChunkWithRetry(sessionId: any, idx: any, chunk: any, attemptsLeft: any, cb: Callback) {
    const self = this;
    self._uploadChunk(sessionId, idx, chunk, function (err, result) {
      if (err) {
        if (attemptsLeft > 1) {
          setTimeout(function () {
            self._uploadChunkWithRetry(sessionId, idx, chunk, attemptsLeft - 1, cb);
          }, 500 * (self.retries - attemptsLeft + 1));
        } else {
          cb(err, null);
        }
      } else {
        cb(null, result);
      }
    });
  }

  _uploadChunk(sessionId: any, idx: any, chunk: any, cb: Callback) {
    const self = this;
    const xhr = new XMLHttpRequest();
    const url = self.endpoint + '/chunks?session=' + sessionId + '&index=' + idx;
    xhr.open('POST', url);
    self._setHeaders(xhr);
    xhr.onload = function () {
      if (xhr.status >= 200 && xhr.status < 300) {
        cb(null, { index: idx, etag: xhr.getResponseHeader('ETag') });
      } else {
        cb(new Error('chunk ' + idx + ' failed: ' + xhr.status), null);
      }
    };
    xhr.onerror = function () {
      cb(new Error('chunk ' + idx + ' network error'), null);
    };
    xhr.send(chunk);
  }

  _finalizeUpload(sessionId: any, cb: Callback) {
    const self = this;
    const xhr = new XMLHttpRequest();
    xhr.open('POST', self.endpoint + '/finalize?session=' + sessionId);
    self._setHeaders(xhr);
    xhr.onload = function () {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          const parsed = JSON.parse(xhr.responseText);
          cb(null, parsed);
        } catch (e) {
          cb(e, null);
        }
      } else {
        cb(new Error('finalize failed: ' + xhr.status), null);
      }
    };
    xhr.onerror = function () {
      cb(new Error('finalize network error'), null);
    };
    xhr.send();
  }

  _splitChunks(file: any): any[] {
    const chunks = [];
    let offset = 0;
    while (offset < file.size) {
      const end = Math.min(offset + this.chunkSize, file.size);
      chunks.push(file.slice(offset, end));
      offset = end;
    }
    return chunks;
  }

  _setHeaders(xhr: any) {
    const self = this;
    Object.keys(self.headers).forEach(function (key) {
      xhr.setRequestHeader(key, self.headers[key]);
    });
  }

  _genId(): any {
    return 'up_' + Date.now() + '_' + Math.random().toString(36).slice(2);
  }

  cancel(uploadId: any, cb: Callback) {
    const self = this;
    if (!self.activeUploads[uploadId]) {
      cb(new Error('no such upload'), null);
      return;
    }
    delete self.activeUploads[uploadId];
    cb(null, { cancelled: true });
  }

  listActive(cb: Callback) {
    cb(null, Object.keys(this.activeUploads));
  }

  uploadMany(files: any, cb: Callback) {
    const self = this;
    const results: any[] = [];
    const errors: any[] = [];
    let i = 0;
    function next() {
      if (i >= files.length) {
        cb(errors.length > 0 ? errors : null, results);
        return;
      }
      const file = files[i++];
      self.upload(file, function (err, result) {
        if (err) {
          errors.push({ file: file.name, error: err });
        } else {
          results.push({ file: file.name, result: result });
        }
        next();
      });
    }
    next();
  }

  // Batch upload with progress aggregation
  uploadBatch(files: any, cb: Callback) {
    const self = this;
    const totalSize = files.reduce(function (acc: any, f: any) { return acc + f.size; }, 0);
    let uploadedSize = 0;
    const results: any[] = [];
    let i = 0;
    function next() {
      if (i >= files.length) {
        cb(null, results);
        return;
      }
      const file = files[i++];
      self.onProgress({
        uploaded: uploadedSize,
        total: totalSize,
        done: false,
      });
      self.upload(file, function (err, result) {
        if (err) {
          cb(err, null);
          return;
        }
        uploadedSize += file.size;
        results.push({ file: file.name, result: result });
        next();
      });
    }
    next();
  }

  // Pause/resume are not supported in this legacy implementation.
  pause(uploadId: any, cb: Callback) {
    cb(new Error('pause not supported'), null);
  }

  resume(uploadId: any, cb: Callback) {
    cb(new Error('resume not supported'), null);
  }

  getStatus(uploadId: any, cb: Callback) {
    const self = this;
    const status = self.activeUploads[uploadId];
    if (!status) {
      cb(new Error('no such upload'), null);
      return;
    }
    cb(null, {
      uploadId: uploadId,
      filename: status.file.name,
      size: status.file.size,
      chunks: status.chunks.length,
      started: status.started,
      elapsed: Date.now() - status.started,
    });
  }

  // Compose URL with query string
  _buildUrl(path: any, params: any): any {
    const self = this;
    const qs = Object.keys(params)
      .map(function (k) { return k + '=' + encodeURIComponent(params[k]); })
      .join('&');
    return self.endpoint + path + (qs ? '?' + qs : '');
  }

  // Synchronous helper — used for tests
  _computeChunksCount(file: any): any {
    return Math.ceil(file.size / this.chunkSize);
  }

  // Validate file before uploading
  _validateFile(file: any, cb: Callback) {
    if (!file) {
      cb(new Error('file is required'), null);
      return;
    }
    if (typeof file.size !== 'number' || file.size <= 0) {
      cb(new Error('invalid file size'), null);
      return;
    }
    cb(null, true);
  }

  // Probe the server for resume capability (legacy: always returns false).
  probeResumeSupport(cb: Callback) {
    const self = this;
    const xhr = new XMLHttpRequest();
    xhr.open('OPTIONS', self.endpoint);
    self._setHeaders(xhr);
    xhr.onload = function () {
      const header = xhr.getResponseHeader('X-Resume-Support');
      cb(null, header === 'true' || header === '1');
    };
    xhr.onerror = function () {
      cb(null, false);
    };
    xhr.send();
  }

  // Probe server to see if an upload session is still valid
  probeSession(sessionId: any, cb: Callback) {
    const self = this;
    const xhr = new XMLHttpRequest();
    xhr.open('GET', self.endpoint + '/sessions/' + sessionId);
    self._setHeaders(xhr);
    xhr.onload = function () {
      if (xhr.status === 200) {
        try {
          cb(null, JSON.parse(xhr.responseText));
        } catch (e) {
          cb(e, null);
        }
      } else if (xhr.status === 404) {
        cb(null, null);
      } else {
        cb(new Error('probe failed: ' + xhr.status), null);
      }
    };
    xhr.onerror = function () {
      cb(new Error('probe network error'), null);
    };
    xhr.send();
  }

  // Aggregate progress across multiple uploads
  aggregateProgress(uploadIds: any[], cb: Callback) {
    const self = this;
    let totalBytes = 0;
    let uploadedBytes = 0;
    const gather = function () {
      totalBytes = 0;
      uploadedBytes = 0;
      for (let i = 0; i < uploadIds.length; i++) {
        const id = uploadIds[i];
        const rec = self.activeUploads[id];
        if (!rec) continue;
        totalBytes += rec.file.size;
        const doneChunks = Math.max(0, rec.chunks.length - 1);
        uploadedBytes += Math.min(rec.file.size, doneChunks * self.chunkSize);
      }
      cb(null, {
        total: totalBytes,
        uploaded: uploadedBytes,
        ratio: totalBytes === 0 ? 0 : uploadedBytes / totalBytes,
      });
    };
    self.onProgress = function () { gather(); };
    gather();
  }

  // Sequential batched uploader that respects a max concurrency of 1
  uploadBatches(batches: any, cb: Callback) {
    const self = this;
    const allResults: any[] = [];
    let batchIdx = 0;
    function nextBatch() {
      if (batchIdx >= batches.length) {
        cb(null, allResults);
        return;
      }
      const batch = batches[batchIdx++];
      self.uploadBatch(batch, function (err, results) {
        if (err) {
          cb(err, null);
          return;
        }
        allResults.push({ batch: batchIdx, results: results });
        nextBatch();
      });
    }
    nextBatch();
  }

  // Throttle helper — wraps a callback so it's called at most every N ms
  _throttle(fn: any, ms: any): any {
    let last = 0;
    let queued: any = null;
    return function () {
      const args = arguments;
      const now = Date.now();
      const remaining = ms - (now - last);
      if (remaining <= 0) {
        last = now;
        fn.apply(null, args);
      } else if (!queued) {
        queued = setTimeout(function () {
          last = Date.now();
          queued = null;
          fn.apply(null, args);
        }, remaining);
      }
    };
  }

  // Build a per-chunk progress callback that aggregates upward
  _makeChunkProgressCallback(uploadId: any, idx: any, total: any): any {
    const self = this;
    return self._throttle(function (loaded: any, chunkSize: any) {
      self.onProgress({
        uploadId: uploadId,
        chunkIndex: idx,
        loaded: loaded,
        chunkSize: chunkSize,
        totalChunks: total,
      });
    }, 200);
  }

  // Generate a unique session ID (used by tests)
  _genSessionId(): any {
    return 'sess_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  }

  // Calculate an exponential backoff delay (used internally by retries)
  _backoffDelay(attempt: any): any {
    const base = 500; // hard-coded in legacy implementation
    return Math.min(30000, base * Math.pow(2, attempt));
  }
}

export { FileUploader };
