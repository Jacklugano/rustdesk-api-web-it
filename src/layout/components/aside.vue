<template>
  <el-scrollbar class="scroll-sidebar" height="100vh">
    <menus></menus>
  </el-scrollbar>
</template>
<script>
  import Menus from '@/layout/components/menu/index.vue'
  import { defineComponent } from 'vue'

  export default defineComponent({
    name: 'GAside',
    components: { Menus },
  })
</script>

<style scoped lang="scss">
.scroll-sidebar {
  background: linear-gradient(180deg, var(--app-sidebar-from) 0%, var(--app-sidebar-to) 100%);
  border-right: 1px solid rgba(255, 255, 255, 0.04);
}

/* Element Plus renders the menu inside the scrollbar, so the theming has to
   reach through :deep() to land on the generated markup. */
.scroll-sidebar :deep(.el-menu) {
  background-color: transparent;
  border-right: none;
  padding: 8px;
}

.scroll-sidebar :deep(.el-sub-menu__title),
.scroll-sidebar :deep(.el-menu-item) {
  color: var(--app-sidebar-text);
  border-radius: var(--app-radius-sm);
  margin-bottom: 4px;
  height: 44px;
  line-height: 44px;
  transition: background-color 0.18s ease, color 0.18s ease;
}

.scroll-sidebar :deep(.el-sub-menu__title:hover),
.scroll-sidebar :deep(.el-menu-item:hover) {
  background-color: rgba(255, 255, 255, 0.06);
  color: var(--app-sidebar-text-active);
}

.scroll-sidebar :deep(.el-menu-item.is-active) {
  background-color: var(--app-sidebar-active);
  color: var(--app-sidebar-text-active);
  font-weight: 500;
  box-shadow: 0 4px 12px rgba(59, 110, 240, 0.35);
}

.scroll-sidebar :deep(.el-menu--inline) {
  background-color: rgba(0, 0, 0, 0.18);
  border-radius: var(--app-radius-sm);
  padding: 4px;
}
</style>
