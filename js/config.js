/* ============================================================================
 *  SCU Maker · 协会展示动画  —  配置文件（你只需要改这一个文件）
 * ----------------------------------------------------------------------------
 *  1. settings  全局设置：Logo 路径、院徽配色、自动播放
 *  2. intro     第一页：Logo 色块快切 + 猫猫工作台动画
 *  3. posters   每个活动一个对象 → 自动生成「中文页 + 英文页」两张
 * ========================================================================== */

window.CONFIG = {

  /* ------------------------------------------------------------------------
   * 1) 全局设置
   * ---------------------------------------------------------------------- */
  settings: {
    autoPlay: true,               // 自动循环播放
    loop: true,                   // 播完最后一页回到第一页
    fullscreenOnStart: false,     // 打开后自动全屏（部分浏览器需用户手势）
    showIntroOnce: false,         // true = 只在第一轮播开场，之后循环跳过

    logoImage: "SCU Maker's Logo.png",   // 协会 Logo（与 index.html 同目录）
    emblemImage: '校徽+院徽（高清+抠图版）.png',  // 左上角排在前面的校徽 + 院徽
    brandBlue: '#4667ad',         // 院徽主蓝
    brandGold: '#f7bd00',         // 院徽金
  },

  /* ------------------------------------------------------------------------
   * 2) 第一页 · 开场
   *    流程：Logo 色块硬切（含川大红 / 优雅灰）→ 敲钉子 → 螺丝刀 → 开心 → 哈气
   *          （每个小猫 1.5s）→ 闪白 → Logo 落位
   *
   *    cuts 里每一项就是一刀（不做过渡动画，直接换色）：
   *      bg     背景色
   *      logo   'black' 黑色 Logo / 'white' 白色 Logo
   *      ghost  背景上巨大的浅色字
   *      ms     这一刀停留多久（毫秒），后面的猫猫动画会自动顺延
   * ---------------------------------------------------------------------- */
  intro: {
    duration: 40700,              // 开场：动画约 9.7s + Logo 停留 10s，然后翻页
    // 开场视频：主用 720p30（Pi 友好），不支持时浏览器自动回退到 540p30
    video: 'assets/动画_web.mp4',
    videoFallback: 'assets/动画_web_540.mp4',
    poster: 'assets/动画_poster.jpg',
    mainTitle: 'SCU Maker',
    subTitle: '四川大学计算机学院（软件学院）开源硬件协会',
    kicker: 'Sichuan University · College of Computer Science',

    // Logo 色块快切
    cuts: [
      { bg: '#f7f4ec', logo: 'black', ghost: 'SCU MAKER', ms: 520 },  // 米白底 · 黑 Logo
      { bg: '#4667ad', logo: 'white', ghost: 'MAKER', ms: 500 },  // 院徽蓝 · 白 Logo
      { bg: '#0a0f22', logo: 'white', ghost: 'SCU MAKER', ms: 500 },  // 夜黑底 · 白 Logo
      { bg: '#f7bd00', logo: 'black', ghost: 'MAKER', ms: 500 },  // 院徽金 · 黑 Logo
      { bg: '#b1281c', logo: 'white', ghost: 'SICHUAN', ms: 460 },  // 川大红 · 白 Logo
      { bg: '#9a9ea6', logo: 'white', ghost: 'MAKER', ms: 460 },  // 优雅灰 · 白 Logo
      { bg: '#f7f4ec', logo: 'black', ghost: 'SCU MAKER', ms: 520 }   // 回到纸面
    ],

    // 落定后的打字机文案轮播
    lines: [
      { text: 'Turn ideas into reality.' },
      { text: 'We think. We design. We make.' }
    ]
  },

  /* ------------------------------------------------------------------------
   * 3) 活动海报：每个活动 = 中文页 + 英文页
   * ------------------------------------------------------------------------
   *  公共字段（两种语言共用）：
   *      date / weekday / weekdayEn / color / duration / image / qr / ongoing
   *      ongoing: true = 该活动「正在进行中」，海报会加上进行中徽标、流光、
   *               呼吸光晕等特效（见 css/style.css 的“进行中”一节）。
   *  zh / en 里各自放这一种语言的全部文字：
   *      tag（左上角标签）, category（同行小字）, title,
   *      speaker, speakerTitle, time, place, description,
   *      highlights[], entry, qrText
   *
   *  · 底部时间栏 = 日期 + 时段，自动拼成「2026年11月22日14:00-17:00」这样的格式。
   *  · title 里用 **文字** 可以加金色下划线强调。
   *  · 想加活动：复制一整个 { ... } 对象即可，页码与进度条会自动增加。
   * ---------------------------------------------------------------------- */
  posters: [
    {
      // 长期举办的活动：date 留空，weekday 写「长期 / Ongoing service」即可
      date: '',
      weekday: '长期',
      weekdayEn: 'Ongoing service',
      // 长期活动（没有具体档期）：不加 ongoing，保持普通海报外观
      color: '#7aa8e8',
      duration: 10000,
      image: '',
      qr: '',

      zh: {
        tag: '创意分享',
        category: '来SCU Maker，分享你的创意',
        title: 'SCU Maker期待您能加入我们，分享您的创意',
        speaker: 'SCU Maker',
        speakerTitle: '',
        time: '',
        place: '“i创街”智能科学创新与开源硬件工坊 & 二基楼B101',
        description: '',
        highlights: [
          '物料提供', '教师指导', '竞赛', '长期开展',
          '无人机', '智能车', '船模',
          'ESP32', 'Arduino', '树莓派', '香橙派',
          'DIY', '焊接', '3D打印'
        ],
        entry: '向全体四川大学师生开放',
        qrText: '向全体四川大学师生开放'
      },

      en: {
        tag: 'Creative Sharing',
        category: 'Come to SCU Maker and Share Your Ideas',
        title: 'SCU Maker Looks Forward to You Joining Us and Sharing Your Ideas',
        speaker: 'SCU Maker',
        speakerTitle: '',
        time: '',
        place: '',
        description: '',
        highlights: [
          'Materials Provided', 'Teacher Guidance', 'Competitions', 'Long-term Operation',
          'Drones', 'Smart Cars', 'Model Boats',
          'ESP32', 'Arduino', 'Raspberry Pi', 'Orange Pi',
          'DIY', 'Soldering', '3D Printing'
        ],
        entry: 'Open to all faculty and students of Sichuan University',
        qrText: 'Open to all faculty and students of Sichuan University'
      }
    },
    {
      date: '2026.11.22',
      weekday: '周日',
      weekdayEn: 'Sun',
      ongoing: true,            // ★ 正在进行中：海报带「进行中」徽标 + 流光 / 光晕特效
      color: '#7aa8e8',
      duration: 10000,
      image: '',
      qr: '',

      zh: {
        tag: '沙龙',
        category: 'Vibe Coding',
        title: '从0到1，用好电脑，开启你的创意之旅',
        speaker: '邓博襦等',
        speakerTitle: 'SCU Maker核心成员',
        time: '19:00 — 21:00',
        place: '四川大学江安校区 · 二基楼B101',
        description: '面向计算机小白展开的计算机基础知识、Vibe Coding技巧与应用开发基础知识分享',
        highlights: ['现场演示', '开放问答'],
        entry: '现场签到',
        qrText: '现场签到'
      },

      en: {
        tag: 'SALON',
        category: 'Vibe Coding',
        title: 'From 0 to 1: Make Good Use of Your Computer and Start Your Creative Journey',
        speaker: 'Boru Deng, etc.',
        speakerTitle: 'Core Member, SCU Maker',
        time: '19:00 — 21:00',
        place: 'Room B101, Building 2, Jiang\'an Campus, Sichuan University',
        description: 'A sharing session for computer beginners covering computer fundamentals, Vibe Coding tips, and application development basics.',
        highlights: ['Live demo', 'Open Q&A'],
        entry: 'Check in on site',
        qrText: 'Check in on site'
      }
    }

  ]
};
