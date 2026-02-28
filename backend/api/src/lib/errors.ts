export class HttpError extends Error {
  public readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
    this.name = 'HttpError';
  }

  static badRequest(message = 'Bad Request') {
    return new HttpError(400, message);
  }

  static notFound(message = 'Not Found') {
    return new HttpError(404, message);
  }

  static forbidden(message = 'Forbidden') {
    return new HttpError(403, message);
  }

  static conflict(message = 'Conflict') {
    return new HttpError(409, message);
  }

  static tooManyRequests(message = 'Too Many Requests') {
    return new HttpError(429, message);
  }
}
