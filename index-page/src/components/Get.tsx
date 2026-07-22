import { site } from '../config';
import { AppleIcon, GitHubIcon } from './Icons';
import { LiveRibbon } from './LiveRibbon';

export function Get() {
  return (
    <section className="get" id="get" aria-labelledby="get-title">
      <div className="get-glow" aria-hidden="true" />
      <div className="get-inner">
        <LiveRibbon size="sm" alive className="get-ribbon" />
        <p className="eyebrow">Get Nerve</p>
        <h2 id="get-title" className="display display--sm">
          Install once.
          <br />
          Glance forever.
        </h2>
        <p className="lede lede--tight get-lede">
          Requires {site.requirements.macos}. Build from source with{' '}
          {site.requirements.xcode}, or wait for the App Store listing.
        </p>

        <div className="get-actions">
          <a
            className="btn btn-line"
            href={site.github}
            target="_blank"
            rel="noreferrer"
            data-testid="download-github"
          >
            <GitHubIcon width={18} height={18} />
            GitHub
          </a>

          {site.appStoreReady ? (
            <a
              className="btn btn-solid"
              href={site.appStore}
              target="_blank"
              rel="noreferrer"
              data-testid="download-appstore"
            >
              <AppleIcon width={18} height={18} />
              App Store
            </a>
          ) : (
            <span
              className="btn btn-solid is-soon"
              data-testid="download-appstore"
              data-href={site.appStore}
              title="App Store listing coming soon"
            >
              <AppleIcon width={18} height={18} />
              App Store
              <i>soon</i>
            </span>
          )}
        </div>
      </div>
    </section>
  );
}
