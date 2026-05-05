'use strict';

require('dotenv').config();

const express = require('express');
const path = require('path');

const app = express();

// Expose the backend URL to the served HTML via a small config endpoint
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3001';

app.get('/config.json', (req, res) => {
  res.json({ backendUrl: BACKEND_URL });
});

app.use(express.static(path.join(__dirname, 'public')));

const PORT = parseInt(process.env.PORT || '3000', 10);
app.listen(PORT, () => {
  console.log(`Joke frontend listening on port ${PORT}`);
  console.log(`Using backend at: ${BACKEND_URL}`);
});
