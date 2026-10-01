// Single source of truth for picture and sound. Times are output seconds unless named `src`.
// Footage coordinates are pixels of the 880×1912 footage frames (2/3 of the 1320×2868 capture).
(function (root) {
  const TL = {
    fps: 30,
    bpm: 120,
    duration: 29,
    footage: { width: 880, height: 1912, fps: 30, frames: 1412 },

    intro: {
      lines: [
        { text: 'Your watch', at: 0.0 },
        { text: 'records.', at: 0.5 },
        { text: 'InsightRun', at: 1.0, accent: true },
        { text: 'explains.', at: 1.5, accent: true },
      ],
      exit: 1.84,
    },

    phoneIn: 2.0,
    phoneOut: 25.5,

    segments: [
      { out: [2.0, 5.0], src: [0.0, 3.0] },
      { out: [5.0, 8.0], src: [3.0, 7.8] },
      { out: [8.0, 10.0], src: [8.6, 10.6] },
      { out: [10.0, 13.5], src: [14.2, 18.2] },
      { out: [13.5, 16.5], src: [18.7, 23.4] },
      { out: [16.5, 17.8], src: [29.75, 31.05], blurIn: true },
      { out: [17.8, 20.6], src: [33.2, 36.0] },
      { out: [20.6, 21.5], src: [36.0, 37.8] },
      { out: [21.5, 25.5], src: [40.6, 45.6] },
    ],

    sections: [
      { index: '01', label: 'Readiness', title: ['Know when', 'to push'], sub: 'Readiness from your HRV and sleep', start: 2.25, end: 5.0 },
      { index: '02', label: 'Signals', title: ['Every signal,', 'one glance'], sub: 'HRV, resting heart rate, sleep, load', start: 5.0, end: 8.0 },
      { index: '03', label: 'Runs', title: ['All your runs,', 'organized'], sub: 'Apple Watch, Strava and more', start: 8.0, end: 10.0 },
      { index: '04', label: 'Coach', title: ['A coach after', 'every run'], sub: 'Feedback and a clear next step', start: 10.0, end: 13.5 },
      { index: '05', label: 'Analysis', title: ['See how the run', 'unfolded'], sub: 'Route, heart rate and splits', start: 13.5, end: 16.5 },
      { index: '06', label: 'Plan', title: ['A plan that', 'adapts to you'], sub: 'Built around your next race', start: 16.5, end: 21.5 },
      { index: '07', label: 'Ask', title: ['Ask your coach', 'anything'], sub: 'Answers grounded in your data', start: 21.5, end: 25.5, ai: true },
    ],

    taps: [
      { src: 8.9, at: [344, 1796] },
      { src: 14.62, at: [280, 902] },
      { src: 33.4, at: [400, 530] },
      { src: 40.72, at: [740, 1606] },
    ],

    zooms: [
      { start: 6.5, end: 8.0, focus: [440, 1090], scale: 1.22 },
      { start: 14.9, end: 16.5, focus: [440, 542], scale: 1.25 },
    ],

    lifts: [
      { start: 3.0, end: 4.75, rect: [32, 392, 816, 580] },
      { start: 11.25, end: 13.35, rect: [36, 1208, 808, 516] },
      { start: 18.75, end: 20.45, rect: [36, 256, 808, 236] },
      { start: 22.75, end: 25.35, rect: [390, 404, 464, 100], ai: true, anchor: 'right' },
      { start: 23.5, end: 25.35, rect: [100, 992, 652, 208], ai: true },
    ],

    end: { start: 25.5, logo: 26.0, wordmark: 'InsightRun', tagline: 'Every run, explained.', footnote: 'Works with Apple Health and Strava' },

    variant: 'dark',
    theme: 'dark',
    footageDir: 'footage',
  };

  // The light take ("EN light app tour", cap_01m3s3np091a0qttn10a98qq5k) follows the same path with
  // other timings, and stops 0.2 s after the coach sheet settles, so its last frame is held.
  TL.variants = {
    dark: {},
    light: {
      theme: 'light',
      footageDir: 'footage-light',
      footage: { width: 880, height: 1912, fps: 30, frames: 1294 },
      segments: [
        { out: [2.0, 5.0], src: [0.0, 3.0] },
        { out: [5.0, 8.0], src: [3.7, 8.5] },
        { out: [8.0, 10.0], src: [9.7, 11.7] },
        { out: [10.0, 13.5], src: [15.2, 19.2] },
        { out: [13.5, 16.5], src: [20.0, 24.7] },
        { out: [16.5, 17.8], src: [31.05, 32.35], blurIn: true },
        { out: [17.8, 20.6], src: [34.4, 37.2] },
        { out: [20.6, 21.5], src: [37.2, 39.0] },
        { out: [21.5, 22.75], src: [41.7, 42.98] },
        { out: [22.75, 25.5], src: [42.98, 42.98] },
      ],
      taps: [
        { src: 10.0, at: [344, 1796] },
        { src: 15.65, at: [280, 902] },
        { src: 34.65, at: [400, 530] },
        { src: 41.97, at: [740, 1606] },
      ],
    },

    // Dark until the run analysis, then the real Settings switch ("EN appearance switch",
    // cap_01m3vdrqaz5aznmsk5gyshxdj2) flips the app on the 18.0 downbeat and the light take carries the rest.
    mix: {
      theme: 'mix',
      duration: 29.5,
      phoneOut: 26.5,
      flip: { at: 18.0, dir: 'footage-switch', point: [508, 810] },
      segments: [
        { out: [2.0, 5.0], src: [0.0, 3.0] },
        { out: [5.0, 8.0], src: [3.0, 7.8] },
        { out: [8.0, 10.0], src: [8.6, 10.6] },
        { out: [10.0, 13.5], src: [14.2, 18.2] },
        { out: [13.5, 16.5], src: [18.7, 23.4] },
        { out: [16.5, 17.3], src: [5.2, 6.0], dir: 'footage-switch', blurIn: true },
        { out: [17.3, 18.0], src: [6.67, 7.37], dir: 'footage-switch' },
        { out: [18.0, 19.0], src: [7.37, 8.37], dir: 'footage-switch' },
        { out: [19.0, 20.0], src: [31.05, 32.05], dir: 'footage-light', blurIn: true },
        { out: [20.0, 23.0], src: [34.4, 37.4], dir: 'footage-light' },
        { out: [23.0, 24.25], src: [41.7, 42.98], dir: 'footage-light' },
        { out: [24.25, 26.5], src: [42.98, 42.98], dir: 'footage-light' },
      ],
      sections: [
        { index: '01', label: 'Readiness', title: ['Know when', 'to push'], sub: 'Readiness from your HRV and sleep', start: 2.25, end: 5.0 },
        { index: '02', label: 'Signals', title: ['Every signal,', 'one glance'], sub: 'HRV, resting heart rate, sleep, load', start: 5.0, end: 8.0 },
        { index: '03', label: 'Runs', title: ['All your runs,', 'organized'], sub: 'Apple Watch, Strava and more', start: 8.0, end: 10.0 },
        { index: '04', label: 'Coach', title: ['A coach after', 'every run'], sub: 'Feedback and a clear next step', start: 10.0, end: 13.5 },
        { index: '05', label: 'Analysis', title: ['See how the run', 'unfolded'], sub: 'Route, heart rate and splits', start: 13.5, end: 16.5 },
        { index: '06', label: 'Appearance', title: ['Light or dark,', 'your call'], sub: 'Pick your theme in Settings', start: 16.5, end: 19.0 },
        { index: '07', label: 'Plan', title: ['A plan that', 'adapts to you'], sub: 'Built around your next race', start: 19.0, end: 23.0 },
        { index: '08', label: 'Ask', title: ['Ask your coach', 'anything'], sub: 'Answers grounded in your data', start: 23.0, end: 26.5, ai: true },
      ],
      taps: [
        { src: 8.9, at: [344, 1796] },
        { src: 14.62, at: [280, 902] },
        { src: 5.5, at: [720, 698], dir: 'footage-switch' },
        { src: 7.3, at: [508, 810], dir: 'footage-switch' },
        { src: 34.65, at: [400, 530], dir: 'footage-light' },
        { src: 41.97, at: [740, 1606], dir: 'footage-light' },
      ],
      lifts: [
        { start: 3.0, end: 4.75, rect: [32, 392, 816, 580] },
        { start: 11.25, end: 13.35, rect: [36, 1208, 808, 516] },
        { start: 21.0, end: 22.85, rect: [36, 256, 808, 236] },
        { start: 24.3, end: 26.35, rect: [390, 404, 464, 100], ai: true, anchor: 'right' },
        { start: 24.9, end: 26.35, rect: [100, 992, 652, 208], ai: true },
      ],
      end: { start: 26.5, logo: 27.0, wordmark: 'InsightRun', tagline: 'Every run, explained.', footnote: 'Works with Apple Health and Strava' },
    },

    // English, light first: the light take for 01-05, "EN appearance switch light to dark"
    // (cap_01m3vpg0max67nhf3e0kxxz6qe) for 06, the dark take for 07-08.
    'mix-ld': {
      theme: 'mix',
      duration: 29.5,
      phoneOut: 26.5,
      flip: { at: 18.0, from: 'light', to: 'dark', point: [508, 894] },
      segments: [
        { out: [2.0, 5.0], src: [0.0, 3.0], dir: 'footage-light' },
        { out: [5.0, 8.0], src: [3.7, 8.5], dir: 'footage-light' },
        { out: [8.0, 10.0], src: [9.7, 11.7], dir: 'footage-light' },
        { out: [10.0, 13.5], src: [15.2, 19.2], dir: 'footage-light' },
        { out: [13.5, 16.5], src: [20.0, 24.7], dir: 'footage-light' },
        { out: [16.5, 17.3], src: [2.1, 2.9], dir: 'footage-switch-ld', blurIn: true },
        { out: [17.3, 18.0], src: [3.14, 3.84], dir: 'footage-switch-ld' },
        { out: [18.0, 19.0], src: [3.867, 4.867], dir: 'footage-switch-ld' },
        { out: [19.0, 20.0], src: [29.75, 30.75], blurIn: true },
        { out: [20.0, 23.0], src: [33.2, 36.2] },
        { out: [23.0, 24.25], src: [40.6, 41.85] },
        { out: [24.25, 26.5], src: [41.85, 44.1] },
      ],
      taps: [
        { src: 10.0, at: [344, 1796], dir: 'footage-light' },
        { src: 15.65, at: [280, 902], dir: 'footage-light' },
        { src: 2.4, at: [720, 698], dir: 'footage-switch-ld' },
        { src: 3.8, at: [508, 894], dir: 'footage-switch-ld' },
        { src: 33.4, at: [400, 530] },
        { src: 40.72, at: [740, 1606] },
      ],
    },

    // French, light first: "FR light app tour" (cap_01m3s3r4wcq0qmz1k3d86tnyqr), then the switch to Sombre
    // ("FR appearance switch", cap_01m3vnxfkqtbspd9c2dgjnh277), then "FR app tour" (cap_01m3rq8a0zfhe6fvzre44ecxz8).
    // The switch take drops its status bar for one frame at 3.833 s, so the cut skips it.
    'mix-fr': {
      theme: 'mix',
      lang: 'fr',
      duration: 29.5,
      phoneOut: 26.5,
      flip: { at: 18.0, from: 'light', to: 'dark', point: [530, 894] },
      intro: {
        lines: [
          { text: 'Ta montre', at: 0.0 },
          { text: 'enregistre.', at: 0.5 },
          { text: 'InsightRun', at: 1.0, accent: true },
          { text: 'explique.', at: 1.5, accent: true },
        ],
        exit: 1.84,
      },
      segments: [
        { out: [2.0, 5.0], src: [0.0, 3.0], dir: 'footage-fr-light' },
        { out: [5.0, 8.0], src: [4.0, 8.8], dir: 'footage-fr-light' },
        { out: [8.0, 10.0], src: [9.7, 11.7], dir: 'footage-fr-light' },
        { out: [10.0, 13.5], src: [15.2, 19.2], dir: 'footage-fr-light' },
        { out: [13.5, 16.5], src: [19.9, 24.4], dir: 'footage-fr-light' },
        { out: [16.5, 17.3], src: [2.1, 2.9], dir: 'footage-fr-switch', blurIn: true },
        { out: [17.3, 18.0], src: [3.1, 3.8], dir: 'footage-fr-switch' },
        { out: [18.0, 19.0], src: [3.87, 4.87], dir: 'footage-fr-switch' },
        { out: [19.0, 20.0], src: [31.1, 32.1], dir: 'footage-fr', blurIn: true },
        { out: [20.0, 23.0], src: [34.4, 37.4], dir: 'footage-fr' },
        { out: [23.0, 24.25], src: [41.7, 42.98], dir: 'footage-fr' },
        { out: [24.25, 26.5], src: [42.98, 45.23], dir: 'footage-fr' },
      ],
      sections: [
        { index: '01', label: 'Disponibilité', title: ['Sache quand', 'accélérer'], sub: 'Ta forme du jour en un score', start: 2.25, end: 5.0 },
        { index: '02', label: 'Signaux', title: ['Tes signaux en', 'un coup d’œil'], sub: 'VFC, cardio, sommeil, charge', start: 5.0, end: 8.0 },
        { index: '03', label: 'Courses', title: ['Toutes tes', 'courses'], sub: 'Apple Watch, Strava et plus', start: 8.0, end: 10.0 },
        { index: '04', label: 'Coach', title: ['Un coach après', 'chaque course'], sub: 'Un retour clair et concret', start: 10.0, end: 13.5 },
        { index: '05', label: 'Analyse', title: ['Revis chaque', 'séance'], sub: 'Parcours, cardio et splits', start: 13.5, end: 16.5 },
        { index: '06', label: 'Apparence', title: ['Clair ou sombre,', 'à toi de voir'], sub: 'Choisis ton thème dans les Réglages', start: 16.5, end: 19.0 },
        { index: '07', label: 'Plan', title: ['Un plan qui', 's’adapte à toi'], sub: 'Construit pour ta course', start: 19.0, end: 23.0 },
        { index: '08', label: 'Coach IA', title: ['Demande à', 'ton coach'], sub: 'Des réponses tirées de ta data', start: 23.0, end: 26.5, ai: true },
      ],
      taps: [
        { src: 10.0, at: [344, 1796], dir: 'footage-fr-light' },
        { src: 15.65, at: [280, 902], dir: 'footage-fr-light' },
        { src: 2.42, at: [720, 698], dir: 'footage-fr-switch' },
        { src: 3.78, at: [530, 894], dir: 'footage-fr-switch' },
        { src: 34.62, at: [400, 530], dir: 'footage-fr' },
        { src: 41.95, at: [740, 1606], dir: 'footage-fr' },
      ],
      lifts: [
        { start: 3.0, end: 4.75, rect: [32, 392, 816, 570] },
        { start: 11.25, end: 13.35, rect: [36, 1208, 808, 516] },
        { start: 21.0, end: 22.85, rect: [36, 256, 808, 236] },
        { start: 24.3, end: 26.35, rect: [184, 404, 664, 128], ai: true, anchor: 'right' },
        { start: 24.9, end: 26.35, rect: [96, 1012, 664, 226], ai: true },
      ],
      end: { start: 26.5, logo: 27.0, wordmark: 'InsightRun', tagline: 'Chaque course, expliquée.', footnote: 'Compatible Apple Santé et Strava' },
    },
  };

  TL.frameCounts = {
    footage: 1412, 'footage-light': 1294, 'footage-switch': 309,
    'footage-fr': 1450, 'footage-fr-light': 1287, 'footage-fr-switch': 285, 'footage-switch-ld': 293,
  };

  TL.variants['mix-ld'] = Object.assign({}, {
    sections: TL.variants.mix.sections,
    lifts: TL.variants.mix.lifts,
    end: TL.variants.mix.end,
  }, TL.variants['mix-ld']);

  TL.useVariant = function (name) {
    const v = TL.variants[name];
    if (!v) throw new Error('unknown variant ' + name);
    Object.assign(TL, v, { variant: name });
    return TL;
  };

  TL.srcAt = function (t) {
    const segs = TL.segments;
    let seg = segs[segs.length - 1], src = seg.src[1];
    if (t < segs[0].out[0]) { seg = segs[0]; src = seg.src[0]; }
    for (const s of segs) {
      if (t >= s.out[0] && t < s.out[1]) {
        const p = (t - s.out[0]) / (s.out[1] - s.out[0]);
        seg = s; src = s.src[0] + p * (s.src[1] - s.src[0]);
        break;
      }
    }
    return { src, dir: seg.dir || TL.footageDir };
  };

  TL.srcTime = function (t) {
    return TL.srcAt(t).src;
  };

  TL.outTime = function (src, dir) {
    const d = dir || TL.footageDir;
    for (const s of TL.segments) {
      if ((s.dir || TL.footageDir) === d && src >= s.src[0] && src < s.src[1]) {
        const p = (src - s.src[0]) / (s.src[1] - s.src[0]);
        return s.out[0] + p * (s.out[1] - s.out[0]);
      }
    }
    return null;
  };

  if (typeof module !== 'undefined') module.exports = TL;
  else root.TL = TL;
})(this);
