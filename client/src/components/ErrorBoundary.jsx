import { Component } from 'react';
import { AlertTriangle } from 'lucide-react';

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('UI error:', error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="rounded-2xl border border-error/40 bg-error/5 p-6 text-center">
          <AlertTriangle className="w-8 h-8 text-error mx-auto mb-3" />
          <p className="font-semibold text-text-primary mb-1">
            {this.props.label || 'Something went wrong'}
          </p>
          <p className="text-sm text-text-secondary mb-4">{this.state.error.message}</p>
          <button
            onClick={() => this.setState({ error: null })}
            className="px-4 py-2 rounded-lg bg-error/20 text-error hover:bg-error/30 transition-colors text-sm font-medium"
          >
            Try again
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
