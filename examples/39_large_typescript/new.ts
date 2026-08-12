// File uploader module — refactored with proper generics, async/await,
// discriminated unions for events and errors, and configurable parallelism.

export interface UploaderConfig {
  readonly endpoint: string;
  readonly chunkSize: number;
  readonly retries: number;
  readonly parallelism: number;
  readonly headers: Readonly<Record<string, string>>;
  readonly metadata: Readonly<Record<string, string>>;
  readonly requestTimeoutMs: number;
  readonly retryBackoffBaseMs: number;
}

export type UploaderOptions = Partial<UploaderConfig>;

export interface UploadInput {
  readonly name: string;
  readonly size: number;
  readonly type: string;
  slice(start: number, end: number): Blob;
}

export interface UploadResult {
  readonly uploadId: string;
  readonly sessionId: string;
  readonly url: string;
  readonly size: number;
  readonly chunkCount: number;
  readonly durationMs: number;
}

export interface UploadStatus {
  readonly uploadId: string;
  readonly filename: string;
  readonly size: number;
  readonly chunkCount: number;
  readonly startedAt: number;
  readonly elapsedMs: number;
  readonly uploadedChunks: number;
  readonly state: UploadState;
}

export type UploadState =
  | { kind: 'pending' }
  | { kind: 'uploading'; uploadedBytes: number }
  | { kind: 'paused'; uploadedBytes: number }
  | { kind: 'completed'; result: UploadResult }
  | { kind: 'failed'; error: UploadError }
  | { kind: 'cancelled'; reason: string };

export type UploadError =
  | { type: 'init_failed'; status: number; message: string }
  | { type: 'chunk_failed'; index: number; status: number; message: string }
  | { type: 'finalize_failed'; status: number; message: string }
  | { type: 'network_error'; stage: 'init' | 'chunk' | 'finalize'; message: string }
  | { type: 'timeout'; stage: 'init' | 'chunk' | 'finalize' }
  | { type: 'invalid_input'; message: string }
  | { type: 'cancelled'; uploadId: string };

export type UploadEvent =
  | { kind: 'init'; uploadId: string; sessionId: string }
  | { kind: 'chunk_start'; uploadId: string; index: number; total: number }
  | { kind: 'chunk_complete'; uploadId: string; index: number; etag: string | null }
  | { kind: 'progress'; uploadId: string; uploadedBytes: number; totalBytes: number }
  | { kind: 'complete'; uploadId: string; result: UploadResult }
  | { kind: 'error'; uploadId: string; error: UploadError }
  | { kind: 'cancelled'; uploadId: string };

export type ProgressCallback = (event: UploadEvent) => void;

const DEFAULTS: UploaderConfig = {
  endpoint: '/api/uploads',
  chunkSize: 4 * 1024 * 1024,
  retries: 3,
  parallelism: 3,
  headers: {},
  metadata: {},
  requestTimeoutMs: 30_000,
  retryBackoffBaseMs: 500,
};

interface ActiveUpload {
  readonly file: UploadInput;
  readonly startedAt: number;
  readonly chunkCount: number;
  readonly chunkStates: ChunkState[];
  state: UploadState;
  abortController: AbortController | null;
}

interface ChunkState {
  index: number;
  status: 'pending' | 'uploading' | 'done' | 'failed';
  etag: string | null;
  attempts: number;
}

class UploadHttpError extends Error {
  constructor(public readonly stage: 'init' | 'chunk' | 'finalize',
              public readonly status: number,
              message: string) {
    super(message);
    this.name = 'UploadHttpError';
  }
}

class UploadNetworkError extends Error {
  constructor(public readonly stage: 'init' | 'chunk' | 'finalize') {
    super(`network error during ${stage}`);
    this.name = 'UploadNetworkError';
  }
}

class UploadTimeoutError extends Error {
  constructor(public readonly stage: 'init' | 'chunk' | 'finalize') {
    super(`timeout during ${stage}`);
    this.name = 'UploadTimeoutError';
  }
}

export class FileUploader {
  private readonly config: UploaderConfig;
  private readonly active = new Map<string, ActiveUpload>();
  private readonly listeners = new Set<ProgressCallback>();

  constructor(opts: UploaderOptions = {}) {
    this.config = { ...DEFAULTS, ...opts };
    if (this.config.chunkSize <= 0) {
      throw new Error('chunkSize must be positive');
    }
    if (this.config.parallelism < 1) {
      throw new Error('parallelism must be at least 1');
    }
    if (this.config.retries < 1) {
      throw new Error('retries must be at least 1');
    }
  }

  on(cb: ProgressCallback): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  private emit(event: UploadEvent): void {
    for (const cb of this.listeners) {
      try {
        cb(event);
      } catch {
        // Listener errors are non-fatal.
      }
    }
  }

  async upload(file: UploadInput): Promise<UploadResult> {
    this.validateFile(file);
    const uploadId = this.genId();
    const chunkCount = Math.ceil(file.size / this.config.chunkSize);
    const chunkStates: ChunkState[] = Array.from({ length: chunkCount }, (_, i) => ({
      index: i, status: 'pending' as const, etag: null, attempts: 0,
    }));
    const record: ActiveUpload = {
      file, startedAt: Date.now(), chunkCount, chunkStates,
      state: { kind: 'pending' },
      abortController: null,
    };
    this.active.set(uploadId, record);

    try {
      const sessionId = await this.initiateUpload(uploadId, file);
      this.emit({ kind: 'init', uploadId, sessionId });
      record.state = { kind: 'uploading', uploadedBytes: 0 };

      await this.uploadChunks(uploadId, sessionId, file, chunkStates);
      const result = await this.finalizeUpload(uploadId, sessionId, file, chunkCount);
      record.state = { kind: 'completed', result };
      this.emit({ kind: 'complete', uploadId, result });
      this.active.delete(uploadId);
      return result;
    } catch (err) {
      const error = this.classifyError(err, uploadId);
      record.state = { kind: 'failed', error };
      this.emit({ kind: 'error', uploadId, error });
      this.active.delete(uploadId);
      throw error;
    }
  }

  cancel(uploadId: string, reason = 'user_request'): boolean {
    const record = this.active.get(uploadId);
    if (!record) return false;
    if (record.abortController) {
      record.abortController.abort();
    }
    record.state = { kind: 'cancelled', reason };
    this.emit({ kind: 'cancelled', uploadId });
    this.active.delete(uploadId);
    return true;
  }

  getStatus(uploadId: string): UploadStatus | null {
    const record = this.active.get(uploadId);
    if (!record) return null;
    const uploadedChunks = record.chunkStates.filter(c => c.status === 'done').length;
    return {
      uploadId,
      filename: record.file.name,
      size: record.file.size,
      chunkCount: record.chunkCount,
      startedAt: record.startedAt,
      elapsedMs: Date.now() - record.startedAt,
      uploadedChunks,
      state: record.state,
    };
  }

  listActive(): string[] {
    return Array.from(this.active.keys());
  }

  async uploadMany(files: readonly UploadInput[]): Promise<UploadOutcome[]> {
    const outcomes: UploadOutcome[] = [];
    for (const file of files) {
      try {
        const result = await this.upload(file);
        outcomes.push({ file: file.name, ok: true, result });
      } catch (err) {
        outcomes.push({ file: file.name, ok: false, error: err as UploadError });
      }
    }
    return outcomes;
  }

  async uploadManyParallel(files: readonly UploadInput[]): Promise<UploadOutcome[]> {
    const queue = [...files.map((file, idx) => ({ file, idx }))];
    const outcomes: UploadOutcome[] = new Array(files.length);
    const workers = Array.from(
      { length: Math.min(this.config.parallelism, files.length) },
      async () => {
        while (queue.length > 0) {
          const item = queue.shift();
          if (!item) break;
          try {
            const result = await this.upload(item.file);
            outcomes[item.idx] = { file: item.file.name, ok: true, result };
          } catch (err) {
            outcomes[item.idx] = {
              file: item.file.name,
              ok: false,
              error: err as UploadError,
            };
          }
        }
      },
    );
    await Promise.all(workers);
    return outcomes;
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  private validateFile(file: UploadInput): asserts file is UploadInput {
    if (!file) {
      const error: UploadError = { type: 'invalid_input', message: 'file is required' };
      throw error;
    }
    if (typeof file.size !== 'number' || file.size <= 0) {
      const error: UploadError = { type: 'invalid_input', message: 'invalid file size' };
      throw error;
    }
    if (typeof file.slice !== 'function') {
      const error: UploadError = {
        type: 'invalid_input', message: 'file.slice is not a function',
      };
      throw error;
    }
  }

  private async initiateUpload(uploadId: string, file: UploadInput): Promise<string> {
    const body = JSON.stringify({
      upload_id: uploadId,
      filename: file.name,
      size: file.size,
      mime_type: file.type,
      metadata: this.config.metadata,
    });
    const res = await this.fetchWithTimeout(
      `${this.config.endpoint}/init`,
      { method: 'POST', headers: this.jsonHeaders(), body },
      'init',
    );
    if (!res.ok) {
      throw new UploadHttpError('init', res.status, `init failed: ${res.status}`);
    }
    const parsed = await res.json() as { session_id: string };
    return parsed.session_id;
  }

  private async uploadChunks(
    uploadId: string,
    sessionId: string,
    file: UploadInput,
    chunkStates: ChunkState[],
  ): Promise<void> {
    const queue = chunkStates.slice();
    const totalBytes = file.size;
    const worker = async () => {
      while (queue.length > 0) {
        const chunkState = queue.shift();
        if (!chunkState) break;
        chunkState.status = 'uploading';
        chunkState.attempts++;
        this.emit({
          kind: 'chunk_start', uploadId,
          index: chunkState.index, total: chunkStates.length,
        });
        const start = chunkState.index * this.config.chunkSize;
        const end = Math.min(start + this.config.chunkSize, totalBytes);
        const blob = file.slice(start, end);
        try {
          const etag = await this.uploadChunk(sessionId, chunkState.index, blob, uploadId);
          chunkState.status = 'done';
          chunkState.etag = etag;
          this.emit({
            kind: 'chunk_complete', uploadId,
            index: chunkState.index, etag,
          });
          const uploadedBytes = chunkStates
            .filter(c => c.status === 'done')
            .reduce((acc, c) => acc + Math.min(this.config.chunkSize, totalBytes - c.index * this.config.chunkSize), 0);
          this.emit({
            kind: 'progress', uploadId, uploadedBytes, totalBytes,
          });
        } catch (err) {
          if (chunkState.attempts < this.config.retries) {
            const backoff = this.config.retryBackoffBaseMs * chunkState.attempts;
            await this.sleep(backoff);
            queue.push(chunkState);
            chunkState.status = 'pending';
          } else {
            chunkState.status = 'failed';
            throw err;
          }
        }
      }
    };
    const workers = Array.from(
      { length: Math.min(this.config.parallelism, chunkStates.length) },
      () => worker(),
    );
    await Promise.all(workers);
  }

  private async uploadChunk(
    sessionId: string,
    index: number,
    blob: Blob,
    uploadId: string,
  ): Promise<string | null> {
    const url = new URL(`${this.config.endpoint}/chunks`, globalThis.location?.origin);
    url.searchParams.set('session', sessionId);
    url.searchParams.set('index', String(index));
    const res = await this.fetchWithTimeout(
      url.toString().replace(globalThis.location?.origin || '', ''),
      {
        method: 'POST',
        headers: this.config.headers,
        body: blob,
      },
      'chunk',
    );
    if (!res.ok) {
      throw new UploadHttpError('chunk', res.status, `chunk ${index} failed: ${res.status}`);
    }
    return res.headers.get('ETag');
  }

  private async finalizeUpload(
    uploadId: string,
    sessionId: string,
    file: UploadInput,
    chunkCount: number,
  ): Promise<UploadResult> {
    const url = `${this.config.endpoint}/finalize?session=${encodeURIComponent(sessionId)}`;
    const res = await this.fetchWithTimeout(
      url,
      { method: 'POST', headers: this.jsonHeaders() },
      'finalize',
    );
    if (!res.ok) {
      throw new UploadHttpError('finalize', res.status, `finalize failed: ${res.status}`);
    }
    const parsed = await res.json() as { url: string };
    return {
      uploadId,
      sessionId,
      url: parsed.url,
      size: file.size,
      chunkCount,
      durationMs: Date.now() - (this.active.get(uploadId)?.startedAt ?? Date.now()),
    };
  }

  private async fetchWithTimeout(
    input: string,
    init: RequestInit,
    stage: 'init' | 'chunk' | 'finalize',
  ): Promise<Response> {
    const controller = new AbortController();
    const record = this.active.values().next().value as ActiveUpload | undefined;
    if (record) record.abortController = controller;
    const timer = setTimeout(
      () => controller.abort(),
      this.config.requestTimeoutMs,
    );
    try {
      return await fetch(input, { ...init, signal: controller.signal });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') {
        throw new UploadTimeoutError(stage);
      }
      throw new UploadNetworkError(stage);
    } finally {
      clearTimeout(timer);
      if (record) record.abortController = null;
    }
  }

  private classifyError(err: unknown, uploadId: string): UploadError {
    if (err instanceof UploadHttpError) {
      if (err.stage === 'init') {
        return { type: 'init_failed', status: err.status, message: err.message };
      }
      if (err.stage === 'chunk') {
        return { type: 'chunk_failed', index: -1, status: err.status, message: err.message };
      }
      return { type: 'finalize_failed', status: err.status, message: err.message };
    }
    if (err instanceof UploadNetworkError) {
      return { type: 'network_error', stage: err.stage, message: err.message };
    }
    if (err instanceof UploadTimeoutError) {
      return { type: 'timeout', stage: err.stage };
    }
    if (typeof err === 'object' && err !== null && 'type' in err) {
      return err as UploadError;
    }
    return { type: 'invalid_input', message: String(err) };
  }

  private jsonHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      ...this.config.headers,
    };
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private genId(): string {
    return `up_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  }
}

export type UploadOutcome =
  | { file: string; ok: true; result: UploadResult }
  | { file: string; ok: false; error: UploadError };

export function isUploadResult(o: UploadOutcome): o is UploadOutcome & { ok: true } {
  return o.ok;
}

export function isUploadError(o: UploadOutcome): o is UploadOutcome & { ok: false } {
  return !o.ok;
}
