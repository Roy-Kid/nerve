import { useEffect } from 'react';
import { BrowserRouter, Navigate, Route, Routes, useParams } from 'react-router-dom';
import { LocaleProvider, useLocale } from './i18n/locale';
import { DocPage } from './pages/DocPage';
import { DocsIndex } from './pages/DocsIndex';
import { DocsLayout } from './pages/DocsLayout';
import { HubPage } from './pages/HubPage';

function HashHome({ hash, lang }: { hash: string; lang?: string }) {
  const { setLocale } = useLocale();

  useEffect(() => {
    if (lang === 'zh' || lang === 'en') setLocale(lang);
  }, [lang, setLocale]);

  return <Navigate to={{ pathname: '/', hash }} replace />;
}

function TmuxHashRedirect() {
  const { lang } = useParams();
  return <HashHome hash="tmux" lang={lang} />;
}

export function App() {
  return (
    <LocaleProvider>
      <BrowserRouter>
      <Routes>
        <Route path="/" element={<HubPage />} />
        <Route path="/macos" element={<HashHome hash="macos" />} />
        <Route path="/tmux" element={<HashHome hash="tmux" />} />
        <Route path="/tmux/:lang" element={<TmuxHashRedirect />} />
        <Route path="/docs" element={<DocsLayout />}>
          <Route index element={<DocsIndex />} />
          <Route path=":slug" element={<DocPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      </BrowserRouter>
    </LocaleProvider>
  );
}
