import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { getTmuxGuidePath } from './config';
import { LocaleProvider, useLocale } from './i18n/locale';
import { DocPage } from './pages/DocPage';
import { DocsIndex } from './pages/DocsIndex';
import { DocsLayout } from './pages/DocsLayout';
import { HubPage } from './pages/HubPage';
import { MacosPage } from './pages/MacosPage';
import { TmuxGuidePage } from './pages/TmuxGuidePage';

function TmuxLocaleRedirect() {
  const { locale } = useLocale();
  return <Navigate to={getTmuxGuidePath(locale)} replace />;
}

export function App() {
  return (
    <LocaleProvider>
      <BrowserRouter>
      <Routes>
        <Route path="/" element={<HubPage />} />
        <Route path="/macos" element={<MacosPage />} />
        <Route path="/tmux" element={<TmuxLocaleRedirect />} />
        <Route path="/tmux/:lang" element={<TmuxGuidePage />} />
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
