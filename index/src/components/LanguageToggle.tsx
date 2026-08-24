import { Languages } from 'lucide-react';
import { useLocation, useNavigate } from 'react-router-dom';
import { locales } from '../i18n/messages';
import { useLocale } from '../i18n/locale';
import { cn } from '../lib/utils';

export function LanguageToggle() {
  const { locale, setLocale, t } = useLocale();
  const location = useLocation();
  const navigate = useNavigate();
  const current = locales.find((l) => l.id === locale) ?? locales[0];

  const chooseLocale = (next: typeof locale) => {
    setLocale(next);
    if (location.pathname.startsWith('/tmux/')) {
      navigate(`/tmux/${next}`);
    }
  };

  return (
    <details className="group relative">
      <summary
        className={cn(
          'focus-ring inline-flex min-h-8 cursor-pointer list-none items-center gap-[0.35rem]',
          'rounded-full px-2 text-xs/[1.55] font-semibold text-label opacity-85',
          'hover:bg-black/5 hover:opacity-100 group-open:bg-black/5 group-open:opacity-100',
          '[&::-webkit-details-marker]:hidden',
        )}
        aria-label={t.nav.switchLanguage}
      >
        <Languages className="size-[15px]" aria-hidden="true" />
        <span>{current.short}</span>
      </summary>
      <div
        className={cn(
          'absolute top-[calc(100%+6px)] right-0 z-[60] min-w-34 rounded-xl border border-black/8',
          'bg-white/95 p-1.5 shadow-[0_12px_40px_rgb(0_0_0/12%)] backdrop-blur-[16px]',
        )}
        role="menu"
      >
        {locales.map((item) => (
          <button
            key={item.id}
            type="button"
            role="menuitemradio"
            aria-checked={locale === item.id}
            className={cn(
              'focus-ring block w-full cursor-pointer rounded-lg px-[0.55rem] py-[0.45rem]',
              'text-left text-[13px] text-label hover:bg-black/5',
              locale === item.id && 'bg-black/5',
            )}
            onClick={() => chooseLocale(item.id)}
          >
            {item.label}
          </button>
        ))}
      </div>
    </details>
  );
}
