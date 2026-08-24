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
    title: ['完整任务队列。', '就在 tmux。'],
    lede: '固定侧栏展示每个任务、状态和等待时间；选中任务后，同一窗口里就能看到最近活动和提示词。',
    docsCta: '打开 tmux 文档',
    priority: {
      title: '侧栏里有什么。',
      items: [
        { tone: 'running', label: '状态筛选', title: '按优先级收窄任务。' },
        { tone: 'attention', label: '活动详情', title: '查看最近事件和提示词。' },
        { tone: 'problem', label: '原地返回', title: '直接选中对应 pane。' },
      ],
    },
    closing: {
      title: '安装和按键，都在文档里。',
      cta: '打开 tmux 文档',
    },
  },
  en: {
    lang: 'en',
    title: ['The whole queue.', 'Inside tmux.'],
    lede:
      'A pinned sidebar shows every job, status, and wait time. Select one to see its latest activity and prompt in the same terminal.',
    docsCta: 'Open tmux docs',
    priority: {
      title: 'What the sidebar shows.',
      items: [
        { tone: 'running', label: 'Status filters', title: 'Narrow the queue by priority.' },
        { tone: 'attention', label: 'Activity detail', title: 'Read the latest event and prompt.' },
        { tone: 'problem', label: 'Pane focus', title: 'Return to the matching pane.' },
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
