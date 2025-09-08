// Shared logging utility for Vite plugins
export interface LoggerOptions {
  pluginName: string;
  enableColors?: boolean;
}

export type LogLevel = "info" | "warn" | "error" | "debug";

const colors = {
  red: (str: string) => `\x1b[31m${str}\x1b[0m`,
  green: (str: string) => `\x1b[32m${str}\x1b[0m`,
  yellow: (str: string) => `\x1b[33m${str}\x1b[0m`,
  blue: (str: string) => `\x1b[34m${str}\x1b[0m`,
  magenta: (str: string) => `\x1b[35m${str}\x1b[0m`,
  cyan: (str: string) => `\x1b[36m${str}\x1b[0m`,
  gray: (str: string) => `\x1b[90m${str}\x1b[0m`,
};

export class Logger {
  private pluginName: string;
  private enableColors: boolean;

  constructor(options: LoggerOptions) {
    this.pluginName = options.pluginName;
    this.enableColors = options.enableColors ?? true;
  }

  private format(level: LogLevel, message: string): string {
    const time = new Date().toLocaleTimeString();
    const prefix = `${time} [${this.pluginName}]`;

    if (!this.enableColors) {
      return `${prefix} ${message}`;
    }

    const colorMap = {
      info: colors.cyan,
      warn: colors.yellow,
      error: colors.red,
      debug: colors.gray,
    };

    const coloredMessage = colorMap[level](message);
    return `${prefix} ${coloredMessage}`;
  }

  info(message: string): void {
    console.log(this.format("info", message));
  }

  warn(message: string): void {
    console.log(this.format("warn", message));
  }

  error(message: string): void {
    console.error(this.format("error", message));
  }

  debug(message: string): void {
    console.log(this.format("debug", message));
  }

  // Convenience method for success messages
  success(message: string): void {
    this.info(message);
  }
}

// Factory function for quick logger creation
export function createLogger(pluginName: string): Logger {
  return new Logger({ pluginName });
}
