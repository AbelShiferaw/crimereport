import { Request, Response, NextFunction } from 'express';
import { ZodSchema, ZodError } from 'zod';

type RequestProperty = 'body' | 'query' | 'params';

export function validate(schema: ZodSchema, property: RequestProperty = 'body') {
  return (req: Request, res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req[property]);

    if (!result.success) {
      const errors = formatZodErrors(result.error);
      res.status(400).json({ error: 'Validation failed', details: errors });
      return;
    }

    req[property] = result.data;
    next();
  };
}

function formatZodErrors(error: ZodError): Array<{ field: string; message: string }> {
  return error.issues.map((issue) => ({
    field: issue.path.join('.'),
    message: issue.message,
  }));
}
