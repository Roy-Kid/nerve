export type Locale = 'en' | 'zh';

export const locales: { id: Locale; label: string; short: string }[] = [
  { id: 'en', label: 'English', short: 'EN' },
  { id: 'zh', label: '中文', short: '中' },
];

type NavCopy = {
  home: string;
  macos: string;
  tmux: string;
  docs: string;
  get: string;
  github: string;
  openMenu: string;
  closeMenu: string;
  productNavigation: string;
  mobileNavigation: string;
  footerNavigation: string;
  switchLanguage: string;
};

type HubSurfaceCopy = {
  kicker: string;
  title: string;
  body: string;
  cta: string;
};

type HubCopy = {
  brand: string;
  tagline: string;
  heroCtaMacos: string;
  heroCtaTmux: string;
  signal: { title: string };
  surfaces: { title: string };
  macos: HubSurfaceCopy;
  tmux: HubSurfaceCopy;
  docs: { title: string; body: string; cta: string };
};

type FooterCopy = {
  download: string;
  tagline: string;
};

type MacosCopy = {
  headline: [string, string];
  subhead: string;
  openDocs: string;
  ribbonPreviewLabel: string;
  storyTitle: string;
  truths: { title: string; body: string }[];
  getTitle: string;
};

type DocsUiCopy = {
  sidebarLabel: string;
  protocol: string;
  overview: string;
  eyebrow: string;
  indexEyebrow: string;
  indexTitle: string;
  indexLede: string;
  pagerLabel: string;
  previous: string;
  next: string;
};

type PreviewJobCopy = {
  name: string;
  detail: string;
  time: string;
};

type PreviewCopy = {
  status: Record<'problem' | 'attention' | 'waiting' | 'running' | 'success' | 'inactive', string>;
  mac: {
    livePreview: string;
    terminalReady: string;
    finder: string;
    file: string;
    edit: string;
    view: string;
    ribbonLabel: string;
    panelLabel: string;
    countsLabel: string;
    jobs: PreviewJobCopy[];
  };
  tmux: {
    label: string;
    filter: string;
    jobs: PreviewJobCopy[];
    activity: string;
    reviewRequested: string;
    checkoutReady: string;
    implementationDone: string;
    testsPassed: string;
    waitingForReview: string;
    prompt: string;
  };
};

export type Messages = {
  nav: NavCopy;
  hub: HubCopy;
  footer: FooterCopy;
  macos: MacosCopy;
  docsUi: DocsUiCopy;
  preview: PreviewCopy;
};

export const messages: Record<Locale, Messages> = {
  en: {
    nav: {
      home: 'Home',
      macos: 'macOS',
      tmux: 'tmux',
      docs: 'Docs',
      get: 'Install',
      github: 'GitHub',
      openMenu: 'Open navigation',
      closeMenu: 'Close navigation',
      productNavigation: 'Product',
      mobileNavigation: 'Product mobile',
      footerNavigation: 'Footer',
      switchLanguage: 'Switch language',
    },
    hub: {
      brand: 'Nerve',
      tagline: 'Every agent. One live view.',
      heroCtaMacos: 'For macOS',
      heroCtaTmux: 'For tmux',
      signal: {
        title: 'See what needs you.',
      },
      surfaces: {
        title: 'Pick your surface.',
      },
      macos: {
        kicker: 'macOS',
        title: 'In the menu bar.',
        body: 'Every job, always in sight.',
        cta: 'View macOS',
      },
      tmux: {
        kicker: 'tmux',
        title: 'In the terminal.',
        body: 'The same live view, inside tmux.',
        cta: 'View tmux',
      },
      docs: {
        title: 'Setup belongs in the docs.',
        body: 'Install, configure, and integrate Nerve there.',
        cta: 'Open docs',
      },
    },
    footer: {
      download: 'Install',
      tagline: 'Open source. Local first.',
    },
    macos: {
      headline: ['Every job.', 'One glance.'],
      subhead: 'Running, waiting, or broken—right in the menu bar.',
      openDocs: 'Open docs',
      ribbonPreviewLabel: 'Live ribbon preview',
      storyTitle: 'Status without another window.',
      truths: [
        { title: 'One live ribbon.', body: 'See every job at a glance.' },
        {
          title: 'Only when it matters.',
          body: 'Running, waiting, and failed stay distinct.',
        },
        {
          title: 'Open and local.',
          body: 'The protocol and source are yours to inspect.',
        },
      ],
      getTitle: 'Everything else is in the docs.',
    },
    docsUi: {
      sidebarLabel: 'Documentation',
      protocol: 'Protocol',
      overview: 'Overview',
      eyebrow: 'Docs',
      indexEyebrow: 'Open protocol',
      indexTitle: 'The whole protocol, written down.',
      indexLede:
        'Install the app, wire agent plugins, push snapshots, and read the exact contract every client reads. Product pages live at /macos and /tmux; this handbook keeps the implementation details in one place.',
      pagerLabel: 'Adjacent docs',
      previous: 'Previous',
      next: 'Next',
    },
    preview: {
      status: {
        problem: 'Problem',
        attention: 'Attention',
        waiting: 'Waiting',
        running: 'Running',
        success: 'Success',
        inactive: 'Inactive',
      },
      mac: {
        livePreview: 'Live preview',
        terminalReady: 'ready · built in 0.10 s',
        finder: 'Finder',
        file: 'File',
        edit: 'Edit',
        view: 'View',
        ribbonLabel: 'Nerve status ribbon',
        panelLabel: 'Nerve status panel preview',
        countsLabel: 'Status counts',
        jobs: [
          { name: 'Deploy preview', detail: 'Health check failed', time: '8 min' },
          { name: 'Unit tests', detail: 'Approval required', time: '1 min' },
          { name: 'Nerve', detail: 'Waiting for input', time: '10 sec' },
          { name: 'Claude Code', detail: 'Editing website', time: '18 sec' },
          { name: 'Build archive', detail: 'Finished cleanly', time: '2 min' },
          { name: 'Local watcher', detail: 'No recent signal', time: '12 min' },
        ],
      },
      tmux: {
        label: 'tmux sidebar preview',
        filter: 'all',
        jobs: [
          { name: 'checkout', detail: 'Implementing auth', time: '3m' },
          { name: 'nerve', detail: 'Needs your review', time: 'now' },
          { name: 'ios-build', detail: 'Tests passed', time: '1m' },
          { name: 'deploy', detail: 'Waiting on API', time: '4m' },
          { name: 'docs', detail: 'Ready', time: '12m' },
        ],
        activity: 'Activity',
        reviewRequested: 'Review requested',
        checkoutReady: 'Checkout flow ready',
        implementationDone: 'agent finished the implementation',
        testsPassed: 'tests passed in 42 seconds',
        waitingForReview: 'waiting for your review',
        prompt: 'Review the change and ship it.',
      },
    },
  },
  zh: {
    nav: {
      home: '首页',
      macos: 'macOS',
      tmux: 'tmux',
      docs: '文档',
      get: '安装',
      github: 'GitHub',
      openMenu: '打开导航',
      closeMenu: '关闭导航',
      productNavigation: '产品',
      mobileNavigation: '移动端产品导航',
      footerNavigation: '页脚',
      switchLanguage: '切换语言',
    },
    hub: {
      brand: 'Nerve',
      tagline: '所有 agent，一眼看清。',
      heroCtaMacos: 'macOS',
      heroCtaTmux: 'tmux',
      signal: {
        title: '谁需要你，一眼看见。',
      },
      surfaces: {
        title: '选你工作的地方。',
      },
      macos: {
        kicker: 'macOS',
        title: '常驻菜单栏。',
        body: '所有任务，始终在眼前。',
        cta: '看 macOS',
      },
      tmux: {
        kicker: 'tmux',
        title: '就在终端里。',
        body: '同一个实时视图，也在 tmux。',
        cta: '看 tmux',
      },
      docs: {
        title: '配置，都在文档里。',
        body: '安装、接入和细节统一放在这里。',
        cta: '打开文档',
      },
    },
    footer: {
      download: '安装',
      tagline: '开源，本地优先。',
    },
    macos: {
      headline: ['所有任务。', '一眼看清。'],
      subhead: '运行、等待还是出错，都在菜单栏里。',
      openDocs: '打开文档',
      ribbonPreviewLabel: '实时状态条预览',
      storyTitle: '状态清楚，不用再开窗口。',
      truths: [
        { title: '一条实时状态条。', body: '所有任务，一眼看清。' },
        { title: '只在关键时刻找你。', body: '运行、等待和失败，始终分得清。' },
        { title: '开放，且完全本地。', body: '协议和源码都可以自己检查。' },
      ],
      getTitle: '其他细节，都在文档里。',
    },
    docsUi: {
      sidebarLabel: '文档',
      protocol: '协议',
      overview: '概览',
      eyebrow: '文档',
      indexEyebrow: '开放协议',
      indexTitle: '整套协议，全部写清。',
      indexLede:
        '安装应用、接入 agent 插件、推送快照，再查看所有客户端共用的准确协议。产品页在 /macos 和 /tmux；这本手册把实现细节集中在一处。',
      pagerLabel: '相邻文档',
      previous: '上一篇',
      next: '下一篇',
    },
    preview: {
      status: {
        problem: '出问题',
        attention: '需要你',
        waiting: '等待中',
        running: '运行中',
        success: '已完成',
        inactive: '未活动',
      },
      mac: {
        livePreview: '实时预览',
        terminalReady: '就绪 · 0.10 秒构建完成',
        finder: '访达',
        file: '文件',
        edit: '编辑',
        view: '显示',
        ribbonLabel: 'Nerve 状态条',
        panelLabel: 'Nerve 状态面板预览',
        countsLabel: '状态计数',
        jobs: [
          { name: '预览部署', detail: '健康检查失败', time: '8 分钟' },
          { name: '单元测试', detail: '需要批准', time: '1 分钟' },
          { name: 'Nerve', detail: '等待输入', time: '10 秒' },
          { name: 'Claude Code', detail: '正在编辑网站', time: '18 秒' },
          { name: '归档构建', detail: '顺利完成', time: '2 分钟' },
          { name: '本地监视器', detail: '最近没有信号', time: '12 分钟' },
        ],
      },
      tmux: {
        label: 'tmux 侧边栏预览',
        filter: '全部',
        jobs: [
          { name: 'checkout', detail: '正在实现认证', time: '3m' },
          { name: 'nerve', detail: '等你审查', time: '现在' },
          { name: 'ios-build', detail: '测试通过', time: '1m' },
          { name: 'deploy', detail: '等待 API', time: '4m' },
          { name: 'docs', detail: '就绪', time: '12m' },
        ],
        activity: '活动',
        reviewRequested: '已请求审查',
        checkoutReady: '结账流程已就绪',
        implementationDone: 'agent 已完成实现',
        testsPassed: '测试已在 42 秒内通过',
        waitingForReview: '正在等待你审查',
        prompt: '审查这次改动并发布。',
      },
    },
  },
};
