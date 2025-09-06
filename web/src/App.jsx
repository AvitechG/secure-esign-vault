
import React, { useEffect, useState } from 'react'

export default function App() {
  const [health, setHealth] = useState(null)
  useEffect(() => {
    fetch('/api/health').then(r => r.json()).then(setHealth).catch(() => setHealth({ status: 'offline' }))
  }, [])
  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', margin: 24 }}>
      <h1>Secure E‑Sign Vault (MVP)</h1>
      <p>API Health: <b>{health ? health.status : '...'}</b></p>
      <section style={{ marginTop: 16 }}>
        <h2>Try it</h2>
        <ol>
          <li>Register: <code>POST /api/auth/register</code></li>
          <li>Login: <code>POST /api/auth/login</code> → get JWT</li>
          <li>Create Tenant: <code>POST /api/tenants</code></li>
        </ol>
        <p>Swagger: <a href="/swagger">/swagger</a></p>
      </section>
    </div>
  )
}
