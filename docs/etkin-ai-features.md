# Etkin.ai AI Assistant Feature Analysis

## Overview
Etkin.ai is an AI-powered customer experience platform built on top of Chatwoot. The following features were observed in the **AI Assistant Editor** interface.

---

## 1. Global Navigation (Left Sidebar)

The left sidebar contains the main application navigation:

- **İçgörüler** (Insights) — Analytics and reporting
- **Konuşmalar** (Conversations) — Chat conversations
- **Siparişler** (Orders) — Order management
- **Yardım Biletleri** (Help Tickets) — Support tickets
- **Asistanlar** (Assistants) — **AI Agents management (current page)**
- **Kampanyalar** (Campaigns) — Marketing campaigns
- **Otomasyon** (Automation) — Workflow automation
- **Bilgi Yönetimi** (Knowledge Management) — Expandable section with:
  - Entegrasyonlar (Integrations)
  - SSS (FAQ)
  - Ürün/Hizmet Kataloğu (Product/Service Catalog)
- **Kişiler** (Contacts) — Contact management
- **Modül Ekle** (Add Module) — Extend functionality
- **Ayarlar** (Settings) — Application settings

Top bar:
- User profile button ("M mahmut")
- Notification bell ("0")
- Back button ("Geri")

---

## 2. AI Assistant Editor — Header

- **Assistant Selector Dropdown** — Switch between assistants (combobox)
- **Model Selector Dropdown** — Choose AI model (combobox)
- **Disabled Action Button** — Likely "Publish" or "Deploy" (disabled when no changes)

---

## 3. AI Assistant Editor — Tabs

### Tab 1: Asistan Eğitimi (Assistant Training) *[Selected]*
This is the main prompt engineering and testing interface.

#### Left Side — Prompt/Instruction Editor
- **Textbox** — Main prompt/instruction editor where the system prompt is written
- **Değişiklikleri Kaydet** (Save Changes) — Disabled until changes are made

#### Right Side — Test Simulator / Conversation Panel
- **Talimat Analizi** (Instruction Analysis) — Analyze the prompt
- **Simülatörü Kapat** (Close Simulator) — Toggle simulator visibility
- **Eğitimi izle** (Watch Training) — Training observation mode
- **Rehber** (Guide) — Help documentation

##### Simulator Toolbar (above chat):
- **Bilgi Tabanında Ara** (Search Knowledge Base) — "Artiron Müşteri Destek ve Ürün Bilgi Rehberi"
- **Kullanıcı Bildirim Aracı** (User Notification Tool) — Linked to "mahmut yilmaz"
- **Sohbeti İnsana Aktar** (Transfer Chat to Human) — Linked to "mahmut yilmaz"
- **attach-file** — File attachment button
- **Konuşmayı Raporla** (Report Conversation) — Report/flag conversation
- **more-options** — Additional options menu

##### Chat Interface:
- **Text input** — "Bir mesaj yazın" (Write a message)
- **Send button**
- **Sesli mesaj kaydet** (Record voice message) — Voice input

##### Test Management (top of simulator):
- **Yeni Test** (New Test) — Start a new test conversation
- **Adı düzenle** (Edit Name) — Rename the test
- **Testi sil** (Delete Test) — Remove the test

---

### Tab 2: Sürüm Ayarları (Version Settings)
Configuration toggles and options for the assistant version:

#### Toggles/Switches:
- **is_response_analysis** — Response analysis enabled
- **answer_as_draft** — Answer as draft (requires human approval)
- **is_auto_capture** — Auto-capture conversations
- **is_follow_up** — Follow-up messages enabled
- **split_long_messages** — Split long messages
- **agent_can_see_client_details** — Agent can see client details
- **is_inform_the_client** — Inform the client
- **agent_can_be_silent** — Agent can be silent

#### Dropdown:
- **Acil Durum Kullanıcılarını Seçin** (Select Emergency Users) — Escalation contacts

#### Actions:
- **Değişiklikleri Kaydet** (Save Changes) — Disabled until changes are made

---

### Tab 3: Ayarlar (Settings)
Danger zone and advanced settings:

- **Agentin Versiyonlarını Kalıcı Olarak Sil** (Permanently Delete Agent Versions) — Destructive action

---

## 4. Key Features Summary

| Feature | Description |
|---------|-------------|
| **Prompt Editor** | Left-side text area for writing system instructions |
| **Live Simulator** | Right-side chat interface for testing the assistant |
| **Knowledge Base Search** | Tool to search connected knowledge bases |
| **User Notification Tool** | Notify specific users |
| **Human Handoff** | Transfer conversation to human agent |
| **Voice Input** | Record voice messages in the simulator |
| **Test Sessions** | Create, rename, delete test conversations |
| **Version Toggles** | Multiple behavioral switches (draft mode, auto-capture, etc.) |
| **Emergency Users** | Select users for escalation |
| **Instruction Analysis** | Analyze prompt quality/completeness |
| **Version Management** | Tabs for training, version settings, and advanced settings |
| **Model Selection** | Dropdown to choose AI model |

---

## 5. Integration with Chatwoot

The platform extends Chatwoot with:
- AI Assistant management sidebar item
- Knowledge base integration
- Human handoff workflows
- Campaign and automation modules
- Product catalog integration

---

*Document generated from browser inspection of etkin.ai AI Assistant Editor*
