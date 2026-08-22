<template>
  <div class="home">
    <!-- intestazione di benvenuto -->
    <div class="hero">
      <div class="hero-text">
        <h2 class="hero-title">{{ T('Welcome') }}, {{ userStore.username }}</h2>
        <p class="hero-subtitle">{{ appStore.setting.title }}</p>
      </div>
    </div>

    <div class="grid">
      <!-- dati dell'utente -->
      <el-card shadow="hover" class="card">
        <template #header>
          <div class="card-header">
            <el-icon class="card-icon">
              <el-icon-user/>
            </el-icon>
            <span>{{ T('Userinfo') }}</span>
          </div>
        </template>

        <div class="field">
          <span class="field-label">{{ T('Username') }}</span>
          <span class="field-value">{{ userStore.username || '—' }}</span>
        </div>
        <div class="field">
          <span class="field-label">{{ T('Email') }}</span>
          <span class="field-value">{{ userStore.email || '—' }}</span>
        </div>
        <div class="field">
          <span class="field-label">{{ T('Password') }}</span>
          <el-button type="primary" plain size="small" @click="showChangePwd">
            {{ T('ChangePassword') }}
          </el-button>
        </div>
      </el-card>

      <!-- valori necessari per configurare i client -->
      <el-card shadow="hover" class="card">
        <template #header>
          <div class="card-header">
            <el-icon class="card-icon">
              <el-icon-setting/>
            </el-icon>
            <span>{{ T('ServerConfig') }}</span>
          </div>
        </template>

        <p class="card-hint">{{ T('ServerConfigTips') }}</p>

        <div v-for="item in serverFields" :key="item.key" class="field">
          <span class="field-label">{{ item.label }}</span>
          <span class="field-value">
            <code class="mono" :class="{ 'is-empty': !item.value }">
              {{ item.value || T('NotConfigured') }}
            </code>
            <el-button
                v-if="item.value"
                class="copy-btn"
                link
                type="primary"
                size="small"
                @click="copy(item.value, $event)">{{ T('Copy') }}</el-button>
          </span>
        </div>
      </el-card>
    </div>

    <!-- collegamento con provider esterni -->
    <el-card shadow="hover" class="card card-block">
      <template #header>
        <div class="card-header">
          <el-icon class="card-icon">
            <el-icon-connection/>
          </el-icon>
          <span>OIDC</span>
        </div>
      </template>

      <el-table :data="oidcData" fit>
        <el-table-column :label="T('IdP')" prop="op" align="center"></el-table-column>
        <el-table-column :label="T('Status')" prop="status" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.status === 1" type="success">{{ T('HasBind') }}</el-tag>
            <el-tag v-else type="info">{{ T('NoBind') }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column :label="T('Actions')" align="center" width="200">
          <template #default="{ row }">
            <el-button v-if="row.status === 1" type="danger" plain size="small" @click="toUnBind(row)">
              {{ T('UnBind') }}
            </el-button>
            <el-button v-else type="success" plain size="small" @click="toBind(row)">
              {{ T('ToBind') }}
            </el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- messaggio di benvenuto configurabile dal server -->
    <el-card v-if="html" shadow="hover" class="card card-block">
      <div class="hello" v-html="html"></div>
    </el-card>

    <changePwdDialog v-model:visible="changePwdVisible"></changePwdDialog>
  </div>
</template>

<script setup>
  import changePwdDialog from '@/components/changePwdDialog.vue'
  import { computed, ref } from 'vue'
  import { useUserStore } from '@/store/user'
  import { useAppStore } from '@/store/app'
  import { bind, unbind } from '@/api/oauth'
  import { myOauth } from '@/api/user'
  import { ElMessageBox } from 'element-plus'
  import { T } from '@/utils/i18n'
  import { marked } from 'marked'
  import { handleClipboard } from '@/utils/clipboard'

  const appStore = useAppStore()
  const userStore = useUserStore()
  const changePwdVisible = ref(false)
  const showChangePwd = () => {
    changePwdVisible.value = true
  }

  // i valori del server arrivano da /config/server, già caricati nello store
  const serverFields = computed(() => {
    const c = appStore.setting.rustdeskConfig || {}
    return [
      { key: 'id_server', label: T('IdServer'), value: c.id_server },
      { key: 'relay_server', label: T('RelayServer'), value: c.relay_server },
      { key: 'api_server', label: T('ApiServer'), value: c.api_server },
      { key: 'key', label: T('Key'), value: c.key },
    ]
  })

  const copy = (text, event) => {
    handleClipboard(text, event)
  }

  const oidcData = ref([])
  const getMyOauth = async () => {
    const res = await myOauth().catch(_ => false)
    if (res) {
      oidcData.value = res.data
    }
  }
  getMyOauth()

  const toBind = async (row) => {
    const res = await bind({ op: row.op }).catch(_ => false)
    if (res) {
      const { url } = res.data
      window.open(url)
    }
  }
  const toUnBind = async (row) => {
    const cf = await ElMessageBox.confirm(T('Confirm?', { param: T('UnBind') }), {
      confirmButtonText: T('Confirm'),
      cancelButtonText: T('Cancel'),
      type: 'warning',
    }).catch(_ => false)
    if (!cf) {
      return false
    }
    const res = await unbind({ op: row.op }).catch(_ => false)
    if (res) {
      getMyOauth()
    }
  }

  const html = computed(_ => marked(appStore.setting.hello || ''))
</script>

<style scoped lang="scss">
.hero {
  margin-bottom: 20px;
}

.hero-title {
  margin: 0 0 4px;
  font-size: 22px;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: var(--app-text);
}

.hero-subtitle {
  margin: 0;
  font-size: 14px;
  color: var(--app-text-muted);
}

/* due colonne su schermi ampi, una sola sotto i 900px */
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr));
  gap: 20px;
}

.card-block {
  margin-top: 20px;
}

.card-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
  font-size: 15px;
}

.card-icon {
  color: var(--el-color-primary);
  font-size: 17px;
}

.card-hint {
  margin: 0 0 16px;
  font-size: 13px;
  color: var(--app-text-muted);
}

.field {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 0;
  border-bottom: 1px solid var(--app-border);

  &:last-child {
    border-bottom: none;
  }
}

.field-label {
  color: var(--app-text-muted);
  font-size: 13px;
  flex-shrink: 0;
}

.field-value {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  font-size: 14px;
  color: var(--app-text);
}

/* la chiave pubblica è lunga: va troncata invece di sfondare la scheda */
.mono {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  font-size: 12px;
  background-color: var(--app-surface-muted);
  border: 1px solid var(--app-border);
  border-radius: 6px;
  padding: 3px 8px;
  max-width: 240px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;

  &.is-empty {
    color: var(--app-text-muted);
    font-style: italic;
  }
}

.copy-btn {
  flex-shrink: 0;
}

.hello {
  font-size: 14px;
  line-height: 1.7;
  color: var(--app-text);
}
</style>
