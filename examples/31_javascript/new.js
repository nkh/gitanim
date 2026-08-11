import express from 'express';
import cors from 'cors';
import morgan from 'morgan';

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(morgan('combined'));
app.use(express.json());

app.get('/', (req, res) => {
    res.json({ message: 'Hello World', version: '2.0.0' });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: process.uptime() });
});

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});

export default app;
