import { defineStore, acceptHMRUpdate } from 'pinia'
import logo from '@/assets/logo.png'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import en from 'element-plus/es/locale/lang/en'
import it from 'element-plus/es/locale/lang/it'
import ko from 'element-plus/es/locale/lang/ko'
import ru from 'element-plus/es/locale/lang/ru'
import fr from 'element-plus/es/locale/lang/fr'
import es from 'element-plus/es/locale/lang/es'
import zhTw from 'element-plus/es/locale/lang/zh-tw'
import { admin, app, server } from '@/api/config'

const langs = {
  'it': { name: 'Italiano', value: it, sideBarWidth: '260px' },
  'en': { name: 'English', value: en, sideBarWidth: '230px' },
  'fr': { name: 'Français', value: fr, sideBarWidth: '280px' },
  'es': { name: 'Español', value: es, sideBarWidth: '280px' },
  'ko': { name: '한국어', value: ko, sideBarWidth: '230px' },
  'ru': { name: 'Русский', value: ru, sideBarWidth: '250px' },
  'zh-CN': { name: '中文', value: zhCn, sideBarWidth: '210px' },
  'zh-TW': { name: '中文繁体', value: zhTw, sideBarWidth: '210px' },
}

const fallbackLang = 'it'

// navigator.language returns region tags such as "it-IT" or "en-US". Matching
// them straight against `langs` fails, which used to leave the UI showing raw
// translation keys, so resolve the region tag down to a supported language.
function resolveLang (raw) {
  if (!raw) return fallbackLang
  if (langs[raw]) return raw
  const base = String(raw).split('-')[0].toLowerCase()
  if (base === 'zh') {
    return /-(tw|hk|mo)$/i.test(raw) ? 'zh-TW' : 'zh-CN'
  }
  const match = Object.keys(langs).find(k => k.toLowerCase() === base)
  return match || fallbackLang
}

const defaultLang = resolveLang(localStorage.getItem('lang') || navigator.language)

export const useAppStore = defineStore({
  id: 'App',
  state: () => ({
    setting: {
      title: 'Rustdesk API Admin',
      hello: '',
      sideIsCollapse: false,
      logo,
      langs: langs,
      lang: defaultLang,
      locale: langs[defaultLang] ? langs[defaultLang] : langs['en'],
      appConfig: {
        web_client: 1,
      },
      rustdeskConfig: {
        'id_server': '',
        'key': '',
        'relay_server': '',
        'api_server': '',
      },
    },
  }),

  actions: {
    sideCollapse () {
      this.setting.sideIsCollapse = !this.setting.sideIsCollapse
    },
    setLang (lang) {
      const resolved = resolveLang(lang)
      this.setting.lang = resolved
      this.setting.locale = langs[resolved]
      localStorage.setItem('lang', resolved)
    },
    changeLang (v) {
      this.setLang(v)
    },
    loadConfig () {
      this.getAppConfig()
      this.getAdminConfig()
      this.loadRustdeskConfig()
    },
    getAppConfig () {
      return app().then(res => {
        this.setting.appConfig = res.data
      })
    },
    getAdminConfig () {
      return admin().then(res => {
        this.replaceAdminTitle(res.data.title)
        this.setting.hello = res.data.hello
      })
    },
    replaceAdminTitle (newTitle) {
      document.title = document.title.replace(`- ${this.setting.title}`, `- ${newTitle}`)
      this.setting.title = newTitle
    },
    async loadRustdeskConfig () {
      const res = await server().catch(_ => false)
      if (res) {
        this.setting.rustdeskConfig = res.data
        const prefix = 'wc-'
        localStorage.setItem(`${prefix}custom-rendezvous-server`, res.data.id_server)
        localStorage.setItem(`${prefix}key`, res.data.key)
        localStorage.setItem(`${prefix}api-server`, res.data.api_server)
      }
    },
  },
})

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAppStore, import.meta.hot))
}
