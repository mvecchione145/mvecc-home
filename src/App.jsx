import { content } from './content.js'

export default function App() {
  const { name, tagline, about, nowPlaying, links } = content

  return (
    <main className="page">
      <header className="header">
        <h1 className="name">{name}</h1>
        {tagline && <p className="tagline">{tagline}</p>}
      </header>

      {about?.length > 0 && (
        <section className="section">
          <h2 className="section-title">About</h2>
          {about.map((paragraph, i) => (
            <p key={i} className="prose">{paragraph}</p>
          ))}
        </section>
      )}

      {nowPlaying?.length > 0 && (
        <section className="section">
          <h2 className="section-title">Now</h2>
          <ul className="list">
            {nowPlaying.map((item, i) => (
              <li key={i}>{item}</li>
            ))}
          </ul>
        </section>
      )}

      {links?.length > 0 && (
        <section className="section">
          <h2 className="section-title">Elsewhere</h2>
          <nav className="links">
            {links.map((link) => (
              <a key={link.label} href={link.href} rel="noreferrer">
                {link.label}
              </a>
            ))}
          </nav>
        </section>
      )}

      <footer className="footer">
        <span>© {new Date().getFullYear()} {name}</span>
      </footer>
    </main>
  )
}
