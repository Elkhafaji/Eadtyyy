'use strict';

const { Pool } = require('pg');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

let pool;
function getPool() {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL || process.env.POSTGRES_URL ||
      Object.entries(process.env).find(([key, value]) => /(?:DATABASE|POSTGRES).*URL|URL.*(?:DATABASE|POSTGRES)/i.test(key) && /^postgres(?:ql)?:\/\//i.test(value || ''))?.[1];
    if (!connectionString) throw new Error('DATABASE_URL is not configured');
    pool = new Pool({ connectionString, max: 3, idleTimeoutMillis: 10000, connectionTimeoutMillis: 10000, ssl: { rejectUnauthorized: false } });
  }
  return pool;
}

function blank() {
  return {
    users: [], appointments: [], queue_tickets: [], visits: [], prescriptions: [],
    medical_files: [], payments: [], notifications: [], messages: [], audit_logs: [],
    settings: { clinicName: 'عيادتي', logo: '', phone: '', address: '', workStart: '09:00',
      workEnd: '17:00', workDays: [0, 1, 2, 3, 4, 5, 6], appointmentDuration: 15,
      dailyLimit: 20, consultationPrice: 200, currency: 'ج.م', bookingOpen: true,
      requireWorkingToday: true, _rev: 0 }
  };
}

function hashPassword(password, salt) {
  return crypto.createHash('sha256').update(`${salt}::${password}`).digest('hex');
}

function seedUsers() {
  const now = new Date().toISOString();
  const adminPassword = process.env.ADMIN_PASSWORD || 'Error404';
  const staffPassword = process.env.STAFF_PASSWORD || 'Staff@2026';
  const patientPassword = process.env.PATIENT_PASSWORD || 'Patient@2026';
  const make = (role, name, email, phone, extra = {}, password = staffPassword) => {
    const salt = crypto.randomUUID();
    return { id: crypto.randomUUID(), role, name, email, phone, active: true, createdAt: now,
      salt, hash: hashPassword(password, salt), ...extra };
  };
  const users = [
    make('admin', 'مدير النظام', process.env.ADMIN_EMAIL || 'admin@example.com', '', {}, adminPassword),
    make('doctor', 'abdelrahman nashaat', 'abdelrahmannashaat2026@gmail.com', '01102841235', { specialty: 'دكتور اعصاب', price: 500, duration: 10, dailyLimit: 30, bookingOpen: true, isWorking: true }),
    make('receptionist', 'nashaat', 'abdelrahmannashaat2028@gmail.com', 'abdelrahmannashaat2026@gmail.com', {}, staffPassword),
    make('doctor', 'عبدالرحمن نشات', 'eldoctor@gmail.com', '01000000003', { specialty: 'دكتور اعصاب', price: 500, duration: 10, dailyLimit: 30, bookingOpen: true, isWorking: true })
  ];
  for (let i = 1; i <= 30; i++) {
    const n = String(i).padStart(2, '0');
    users.push(make('patient', `مريض ${n}`, `patient${n}@eyadaty.local`, `0110000${String(i).padStart(4, '0')}`, {}, patientPassword));
  }
  return users;
}

async function ensureTable(client) {
  await client.query(`CREATE TABLE IF NOT EXISTS eyadaty_app_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    payload JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`);
}

async function ensureMigrations(client) {
  await client.query('CREATE TABLE IF NOT EXISTS eyadaty_schema_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())');
  const files = ['001_organization_rbac.sql', '002_operational_modules.sql', '003_clinic_core.sql'];
  for (const name of files) {
    const exists = await client.query('SELECT 1 FROM eyadaty_schema_migrations WHERE name = $1', [name]);
    if (!exists.rowCount) {
      const candidates = [
        path.join(__dirname, '..', 'migrations', name),
        path.join(process.cwd(), 'migrations', name)
      ];
      const migrationPath = candidates.find(file => fs.existsSync(file));
      if (!migrationPath) {
        console.warn(`Optional migration file not bundled: ${name}`);
        continue;
      }
      const sql = fs.readFileSync(migrationPath, 'utf8');
      await client.query(sql);
      await client.query('INSERT INTO eyadaty_schema_migrations (name) VALUES ($1)', [name]);
    }
  }
  const orgTable = await client.query(`SELECT to_regclass('public.organizations') AS name`);
  if (!orgTable.rows[0]?.name) return;
  const org = await client.query('SELECT id FROM organizations ORDER BY created_at LIMIT 1');
  if (!org.rowCount) {
    const organizationId = crypto.randomUUID();
    const branchId = crypto.randomUUID();
    await client.query('INSERT INTO organizations (id, name) VALUES ($1, $2)', [organizationId, 'عيادتي']);
    await client.query('INSERT INTO branches (id, organization_id, name, code) VALUES ($1, $2, $3, $4)', [branchId, organizationId, 'الفرع الرئيسي', 'MAIN']);
  }
  const organization = await client.query('SELECT id FROM organizations ORDER BY created_at LIMIT 1');
  const clinicTable = await client.query(`SELECT to_regclass('public.clinics') AS name`);
  if (organization.rowCount && clinicTable.rows[0]?.name) {
    await client.query(`INSERT INTO clinics (id, organization_id, name)
      SELECT $1, $2, $3
      WHERE NOT EXISTS (SELECT 1 FROM clinics WHERE organization_id = $2)`,
      [crypto.randomUUID(), organization.rows[0].id, 'عيادتي']);
  }
}

async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  let client;
  try {
    client = await getPool().connect();
    await ensureTable(client);
    await ensureMigrations(client);
    if (req.method === 'GET') {
      const result = await client.query('SELECT payload FROM eyadaty_app_state WHERE id = 1');
      if (!result.rowCount) {
        const state = blank();
        state.users = seedUsers();
        await client.query('INSERT INTO eyadaty_app_state (id, payload) VALUES (1, $1::jsonb)', [JSON.stringify(state)]);
        return res.status(200).json(state);
      }
      const state = result.rows[0].payload;
      const seededUsers = seedUsers();
      const currentUsers = Array.isArray(state.users) ? state.users : [];
      const knownEmails = new Set(currentUsers.map(user => String(user.email || '').toLowerCase()).filter(Boolean));
      const missingUsers = seededUsers.filter(user => !knownEmails.has(String(user.email || '').toLowerCase()));
      if (missingUsers.length || !Array.isArray(state.users)) {
        state.users = currentUsers.concat(missingUsers);
        await client.query('UPDATE eyadaty_app_state SET payload = $1::jsonb, updated_at = NOW() WHERE id = 1', [JSON.stringify(state)]);
      }
      return res.status(200).json(state);
    }
    if (req.method === 'PUT') {
      const state = req.body;
      if (!state || typeof state !== 'object' || !Array.isArray(state.users)) return res.status(400).json({ error: 'invalid database payload' });
      await client.query(`INSERT INTO eyadaty_app_state (id, payload, updated_at) VALUES (1, $1::jsonb, NOW())
        ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()`, [JSON.stringify(state)]);
      return res.status(200).json({ ok: true });
    }
    res.setHeader('Allow', 'GET, PUT');
    return res.status(405).json({ error: 'method not allowed' });
  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'database request failed' });
  } finally {
    if (client) client.release();
  }
}

module.exports = handler;
