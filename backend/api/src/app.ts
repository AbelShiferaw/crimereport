import 'express-async-errors';
import express from 'express';
import compression from 'compression';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config';
import { requestId } from './middleware/request-id';
import { requestLogger } from './middleware/request-logger';
import { globalLimiter } from './middleware/rate-limit';
import { notFoundHandler } from './middleware/not-found';
import { errorHandler } from './middleware/error-handler';
import healthRouter from './routes/health';
import apiRouter from './routes';

const app = express();

app.use(requestId);
app.use(helmet());
app.use(compression());
app.use(cors({ origin: config.corsOrigin }));
app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);

app.use(healthRouter);
app.use('/api/v1', globalLimiter, apiRouter);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
