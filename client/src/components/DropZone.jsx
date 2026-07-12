import { useState, useRef } from 'react';
import { Upload, Link, Loader2, X, Plus } from 'lucide-react';
import { api } from '../hooks/useApi';
import { useDownloadStore } from '../stores/downloadStore';

export default function DropZone() {
  const [url, setUrl] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState(null);
  const inputRef = useRef(null);
  const addNotification = useDownloadStore((state) => state.addNotification);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!url.trim()) return;

    setIsLoading(true);
    setError(null);

    try {
      // Parse URLs - support multiple URLs separated by newlines
      const urls = url
        .split('\n')
        .map((u) => u.trim())
        .filter((u) => u.length > 0);

      if (urls.length === 0) {
        throw new Error('Please enter at least one valid URL');
      }

      // Validate URLs
      for (const urlStr of urls) {
        try {
          new URL(urlStr);
        } catch {
          throw new Error(`Invalid URL: ${urlStr}`);
        }
      }

      await api.addDownloads(urls);
      setUrl('');
      addNotification({
        type: 'info',
        title: 'Downloads Started',
        message: `${urls.length} download(s) queued`
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleDragOver = (e) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = (e) => {
    e.preventDefault();
    setIsDragging(false);
  };

  const handleDrop = async (e) => {
    e.preventDefault();
    setIsDragging(false);

    const files = Array.from(e.dataTransfer.files);
    const textFiles = files.filter((f) => f.type === 'text/plain' || f.name.endsWith('.txt'));

    if (textFiles.length > 0) {
      const content = await Promise.all(
        textFiles.map((f) => f.text())
      );
      const urls = content
        .join('\n')
        .split('\n')
        .map((u) => u.trim())
        .filter((u) => u.length > 0 && u.startsWith('http'));

      if (urls.length > 0) {
        setUrl(urls.join('\n'));
        addNotification({
          type: 'info',
          title: 'URLs Imported',
          message: `${urls.length} URLs loaded from file`
        });
      }
    }
  };

  const handlePaste = (e) => {
    // Auto-submit on paste if it looks like a URL
    const pastedText = e.clipboardData.getData('text');
    if (pastedText.startsWith('http')) {
      setTimeout(() => {
        handleSubmit({ preventDefault: () => {} });
      }, 100);
    }
  };

  const clearInput = () => {
    setUrl('');
    setError(null);
    inputRef.current?.focus();
  };

  return (
    <div
      className={`
        relative rounded-2xl border-2 border-dashed transition-all duration-300
        ${isDragging 
          ? 'border-accent bg-accent/5 drop-zone-active' 
          : error 
            ? 'border-error bg-error/5' 
            : 'border-border-subtle bg-bg-secondary/50 hover:border-accent/50 hover:bg-bg-secondary'
        }
      `}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <form onSubmit={handleSubmit} className="p-6 sm:p-8">
        {/* Icon */}
        <div className="flex justify-center mb-4">
          <div className={`
            w-16 h-16 rounded-2xl flex items-center justify-center transition-all duration-300
            ${isDragging 
              ? 'bg-accent/20 scale-110' 
              : error 
                ? 'bg-error/20' 
                : 'bg-bg-tertiary'
            }
          `}>
            {isLoading ? (
              <Loader2 className="w-8 h-8 text-accent animate-spin" />
            ) : error ? (
              <X className="w-8 h-8 text-error" />
            ) : isDragging ? (
              <Plus className="w-8 h-8 text-accent" />
            ) : (
              <Upload className="w-8 h-8 text-text-secondary" />
            )}
          </div>
        </div>

        {/* Title */}
        <div className="text-center mb-4">
          <h2 className={`text-lg font-semibold mb-1 ${error ? 'text-error' : 'text-text-primary'}`}>
            {isDragging 
              ? 'Drop to add downloads' 
              : error 
                ? 'Error' 
                : 'Add Downloads'
            }
          </h2>
          <p className="text-sm text-text-secondary">
            {isDragging 
              ? 'Release to start downloading' 
              : error 
                ? error 
                : 'Paste URLs or drag & drop a .txt file with URLs'
            }
          </p>
        </div>

        {/* Input Area */}
        <div className="relative max-w-3xl mx-auto">
          <div className="absolute left-4 top-1/2 -translate-y-1/2">
            <Link className="w-5 h-5 text-text-muted" />
          </div>
          
          <textarea
            ref={inputRef}
            type="text"
            value={url}
            onChange={(e) => {
              setUrl(e.target.value);
              setError(null);
            }}
            onPaste={handlePaste}
            placeholder="https://example.com/file.zip&#10;Paste multiple URLs (one per line)"
            className={`
              w-full pl-12 pr-12 py-4 bg-bg-primary rounded-xl border transition-all duration-200
              resize-none h-24 sm:h-auto
              placeholder:text-text-muted text-sm
              ${error 
                ? 'border-error focus:border-error' 
                : 'border-border-subtle focus:border-accent'
              }
              focus:ring-2 focus:ring-accent/20
            `}
            disabled={isLoading}
          />

          {url && (
            <button
              type="button"
              onClick={clearInput}
              className="absolute right-4 top-1/2 -translate-y-1/2 p-1 rounded-lg hover:bg-bg-tertiary transition-colors"
            >
              <X className="w-4 h-4 text-text-muted" />
            </button>
          )}
        </div>

        {/* Submit Button */}
        <div className="flex justify-center mt-4">
          <button
            type="submit"
            disabled={!url.trim() || isLoading}
            className={`
              px-8 py-3 rounded-xl font-semibold transition-all duration-200
              flex items-center gap-2
              ${url.trim() && !isLoading
                ? 'bg-gradient-to-r from-accent to-success text-bg-primary hover:shadow-lg hover:shadow-accent/30 hover:scale-105'
                : 'bg-bg-tertiary text-text-muted cursor-not-allowed'
              }
            `}
          >
            {isLoading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                Processing...
              </>
            ) : (
              <>
                <Zap className="w-5 h-5" />
                Start Download
              </>
            )}
          </button>
        </div>
      </form>

      {/* Drag Overlay */}
      {isDragging && (
        <div className="absolute inset-0 flex items-center justify-center rounded-2xl bg-accent/10 pointer-events-none">
          <div className="text-center">
            <Plus className="w-16 h-16 text-accent mx-auto mb-2" />
            <p className="text-accent font-semibold">Drop to add</p>
          </div>
        </div>
      )}
    </div>
  );
}
