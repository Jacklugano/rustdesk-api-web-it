<template>
  <el-icon class="ex-icon" @click="expandOrFoldSlider">
    <el-icon-expand v-if="setting.sideIsCollapse"></el-icon-expand>
    <el-icon-fold v-else></el-icon-fold>
  </el-icon>
  <div class="header-logo">
    <img :src="setting.logo" alt="" class="logo">
    <div class="title">{{ setting.title }}</div>
  </div>
  <Setting></Setting>
</template>

<script>
  import { defineComponent, computed } from 'vue'
  import HeaderMenu from '@/layout/components/menu/index.vue'
  import Setting from '@/layout/components/setting/index.vue'
  import { useAppStore } from '@/store/app'
  import GTags from '@/layout/components/tags/index.vue'

  export default defineComponent({
    name: 'LayerHeader',
    components: { HeaderMenu, Setting, GTags },
    setup () {
      const appStore = useAppStore()
      const setting = computed(() => appStore.setting)
      const expandOrFoldSlider = () => {
        appStore.sideCollapse()
      }
      return {
        setting,
        expandOrFoldSlider,
      }
    },
  })
</script>

<style scoped lang="scss">
  .ex-icon {
    height: 36px;
    width: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-right: 12px;
    font-size: 18px;
    cursor: pointer;
    border-radius: var(--app-radius-sm);
    color: var(--app-text-muted);
    transition: background-color 0.18s ease, color 0.18s ease;

    &:hover {
      background-color: var(--app-surface-muted);
      color: var(--app-text);
    }
  }

  .header-logo {
    display: flex;
    height: 100%;
    align-items: center;
    gap: 10px;

    .title {
      display: block;
      font-size: 16px;
      font-weight: 600;
      letter-spacing: -0.01em;
      color: var(--app-header-text);
      white-space: nowrap;
    }

    .logo {
      display: block;
      width: 30px;
      height: 30px;
      border-radius: 6px;
    }
  }
</style>
