import { Link } from 'react-router-dom';
import { site } from '../config';
import { LiveRibbon } from './LiveRibbon';
import { useLocale } from '../i18n/locale';
import { productCta, productCtaRow, productSectionTitle } from '../lib/ui';

export function Get() {
  const { t } = useLocale();

  return (
    <section
      className="bg-page px-[var(--page-gutter)] py-[clamp(4rem,10vw,7rem)]"
      id="get"
      aria-labelledby="get-title"
    >
      <div className="mx-auto w-[min(100%,var(--container-page))] max-w-[40rem] text-center">
        <LiveRibbon size="sm" alive className="mx-auto mb-6 max-w-[18rem]" />
        <h2 id="get-title" className={`${productSectionTitle} text-center`}>
          {t.macos.getTitle}
        </h2>

        <div className={productCtaRow}>
          <Link to="/docs/get-started" className={productCta} data-testid="install-docs">
            {t.macos.openDocs}
          </Link>
          <a
            className={productCta}
            href={site.github}
            target="_blank"
            rel="noreferrer"
            data-testid="download-github"
          >
            GitHub
          </a>
        </div>
      </div>
    </section>
  );
}
