<template>
  <el-config-provider :locale="appStore.setting.locale.value">
    <el-container :style="{'--sideBarWidth': sideBarWidth}"
                  :class="{ 'is-mobile': isMobile }">
      <el-aside :width="leftWidth" class="app-left"
                :class="{ 'mobile-open': isMobile && !collapsed }">
        <g-aside></g-aside>
      </el-aside>

      <!-- su mobile la barra e' un overlay: lo sfondo scuro la chiude al tocco -->
      <div v-if="isMobile && !collapsed" class="mobile-backdrop"
           @click="appStore.sideCollapse()"></div>

      <el-container class="app-container">
        <el-header class="app-header">
          <g-header></g-header>
        </el-header>
        <div class="header-tags">
          <tags></tags>
        </div>

        <el-main class="app-main">
          <router-view v-slot="{ Component }">
            <transition mode="out-in" name="el-fade-in-linear">
              <keep-alive :include="cachedTags">
                <component :is="Component"/>
              </keep-alive>
            </transition>
          </router-view>
        </el-main>
      </el-container>
    </el-container>
  </el-config-provider>
</template>

<script setup>
  import { useAppStore } from '@/store/app'
  import { useTagsStore } from '@/store/tags'
  import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
  import { useRoute } from 'vue-router'
  import Tags from '@/layout/components/tags/index.vue'
  import GAside from '@/layout/components/aside.vue'
  import GHeader from '@/layout/components/header.vue'

  const appStore = useAppStore()
  const tagStore = useTagsStore()
  const sideBarWidth = computed(() => appStore.setting.locale.sideBarWidth)
  const collapsed = computed(() => appStore.setting.sideIsCollapse)

  // Sotto i 768px la barra diventa un overlay a scomparsa. Su mobile la sua
  // larghezza e' forzata via CSS, quindi qui basta un valore qualsiasi non nullo.
  const isMobile = ref(false)
  const leftWidth = computed(() => {
    if (isMobile.value) return 'var(--sideBarWidth)'
    return collapsed.value ? '64px' : 'var(--sideBarWidth)'
  })

  const aggiornaViewport = () => {
    const mobile = window.innerWidth <= 768
    // entrando in modalita' mobile la barra parte chiusa, altrimenti coprirebbe
    // subito lo schermo; tornando al desktop la si riapre
    if (mobile !== isMobile.value) {
      isMobile.value = mobile
      appStore.setting.sideIsCollapse = mobile
    }
  }

  onMounted(() => {
    aggiornaViewport()
    window.addEventListener('resize', aggiornaViewport)
  })
  onUnmounted(() => window.removeEventListener('resize', aggiornaViewport))

  // su mobile, dopo aver scelto una voce si chiude la barra, che altrimenti
  // resterebbe a coprire la pagina appena aperta
  const route = useRoute()
  watch(() => route.path, () => {
    if (isMobile.value) appStore.setting.sideIsCollapse = true
  })

  const cachedTags = ref([])
  cachedTags.value = tagStore.cached
</script>

<style lang="scss" scoped>
.app-header {
  background-color: var(--app-header-bg);
  color: var(--app-header-text);
  display: flex;
  align-items: center;
  height: 60px;
  border-bottom: 1px solid var(--app-border);
  box-shadow: 0 1px 2px rgba(16, 24, 40, 0.03);
  position: sticky;
  top: 0;
  z-index: 10;
}

.header-tags {
  height: auto;
  background-color: var(--app-surface);
  border-bottom: 1px solid var(--app-border);
  display: flex;
  padding: 0;
}

.app-left {
  transition: width 0.28s cubic-bezier(0.4, 0, 0.2, 1);
  overflow: hidden;
}

.app-container {
  min-height: 100vh;
  background-color: var(--app-bg);
  min-width: 0;   /* evita che tabelle larghe sfondino il layout flex */
}

.app-main {
  padding: 20px;
}

/* ---- mobile: barra laterale a scomparsa ---- */
.is-mobile {
  .app-left {
    position: fixed;
    top: 0;
    left: 0;
    height: 100vh;
    width: var(--sideBarWidth) !important;
    max-width: 82vw;
    z-index: 2000;
    transform: translateX(-100%);
    transition: transform 0.28s cubic-bezier(0.4, 0, 0.2, 1);
    box-shadow: 2px 0 16px rgba(0, 0, 0, 0.25);
  }

  .app-left.mobile-open {
    transform: translateX(0);
  }
}

.mobile-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  z-index: 1999;
}

@media (max-width: 768px) {
  .app-main {
    padding: 12px;
  }
}
</style>
