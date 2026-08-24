/** Bilingual product copy for the tmux page. Setup and controls live in /docs/tmux. */

export type TmuxGuideLang = 'zh' | 'en';

type PriorityItem = {
  tone: 'running' | 'attention' | 'problem';
  label: string;
  title: string;
};

export type TmuxGuide = {
  lang: TmuxGuideLang;
  title: [string, string];
  lede: string;
  docsCta: string;
  priority: {
    title: string;
    items: PriorityItem[];
  };
  closing: {
    title: string;
    cta: string;
  };
};

export const tmuxGuides: Record<TmuxGuideLang, TmuxGuide> = {
  zh: {
    lang: 'zh',
    title: ['少盯进度。', '多做成事。'],
    lede: '所有任务，一眼看清。',
    docsCta: '打开 tmux 文档',
    priority: {
      title: '运行、等待、处理。',
      items: [
        { tone: 'running', label: '运行中', title: '继续跑。' },
        { tone: 'attention', label: '需要你', title: '回来接手。' },
        { tone: 'problem', label: '出问题', title: '先处理它。' },
      ],
    },
    closing: {
      title: '安装和按键，都在文档里。',
      cta: '打开 tmux 文档',
    },
  },
  en: {
    lang: 'en',
    title: ['Stop checking panes.', 'Get more done.'],
    lede: 'Every job, at a glance.',
    docsCta: 'Open tmux docs',
    priority: {
      title: 'Run. Wait. Act.',
      items: [
        { tone: 'running', label: 'Running', title: 'Keep moving.' },
        { tone: 'attention', label: 'Needs you', title: 'Step back in.' },
        { tone: 'problem', label: 'Problem', title: 'Fix this first.' },
      ],
    },
    closing: {
      title: 'Setup and keys are in the docs.',
      cta: 'Open tmux docs',
    },
  },
};

export function getTmuxGuide(lang: string): TmuxGuide | undefined {
  if (lang === 'zh' || lang === 'en') return tmuxGuides[lang];
  return undefined;
}
