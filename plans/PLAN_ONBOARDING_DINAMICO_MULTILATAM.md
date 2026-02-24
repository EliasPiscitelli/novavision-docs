# Plan de Implementación: Onboarding Dinámico Multi-LATAM

**Fecha:** 2026-02-24  
**Autor:** Copilot Agent  
**Rama:** `feature/automatic-multiclient-onboarding`  
**Repos afectados:** API (templatetwobe) + Admin (novavision)  
**Estado:** Propuesta para validación del TL

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Diagnóstico Actual](#2-diagnóstico-actual)
3. [Validaciones por País — Referencia Completa](#3-validaciones-por-país--referencia-completa)
4. [Diseño de DB: Migraciones Requeridas](#4-diseño-de-db-migraciones-requeridas)
5. [Cambios en Backend (API)](#5-cambios-en-backend-api)
6. [Cambios en Frontend (Admin)](#6-cambios-en-frontend-admin)
7. [Suscripciones MP Multi-País](#7-suscripciones-mp-multi-país)
8. [3 Fixes de Seguridad (Riesgos ALTOS)](#8-3-fixes-de-seguridad-riesgos-altos)
9. [Impacto en PreApproval y Billing](#9-impacto-en-preapproval-y-billing)
10. [Fases de Implementación](#10-fases-de-implementación)
11. [Acciones Manuales del TL](#11-acciones-manuales-del-tl)
12. [Testing y QA](#12-testing-y-qa)
13. [Riesgos y Mitigaciones](#13-riesgos-y-mitigaciones)

---

## 1. Resumen Ejecutivo

El onboarding actual (Step8: Datos del Cliente) está **100% hardcodeado para Argentina**. Los 10 valores hardcodeados son:

| # | Elemento | Valor actual |
|---|----------|-------------|
| 1 | Regex fiscal ID | `^\d{11}$` (CUIT) |
| 2 | Label fiscal ID | "CUIT/CUIL" |
| 3 | Categorías persona | `fisica` / `juridica` |
| 4 | Condición fiscal | `monotributista`, `responsable_inscripto`, `exento`, `no_responsable` |
| 5 | Subdivisiones | 24 provincias argentinas hardcodeadas |
| 6 | Placeholder teléfono | `+54 11 1234-5678` |
| 7 | Placeholder fiscal ID | `20-12345678-9` |
| 8 | Labels AFIP | "Nombre legal según AFIP" |
| 9 | DNI format | `^\d{7,8}$` |
| 10 | Textos legales | "normativas argentinas" |

Además, el sistema de suscripciones en MercadoPago está ligado a un **único token MLA** y hardcodea `currency_id: 'ARS'`.

Este plan cubre:
- **A)** Hacer el onboarding dinámico: el formulario se adapta según el país de la cuenta
- **B)** Crear catálogos de datos por país en la DB (fiscal IDs, subdivisiones, categorías fiscales)
- **C)** Preparar suscripciones MP para multi-moneda/multi-site
- **D)** Resolver 3 vulnerabilidades de seguridad ALTAS

**Países soportados:** AR 🇦🇷, CL 🇨🇱, MX 🇲🇽, CO 🇨🇴, UY 🇺🇾, PE 🇵🇪

---

## 2. Diagnóstico Actual

### 2.1 Lo que YA está listo ✅

| Componente | Estado | Detalle |
|-----------|--------|---------|
| `country_configs` (tabla) | ✅ Creada | 6 países con site_id, currency, locale, timezone, decimals |
| `fx_rates_config` (tabla) | ✅ Creada | Endpoints de conversión USD→local para 6 países |
| `FxService v2` | ✅ Multi-país | `getRate(countryId)` y `convertUsdToLocal(usd, countryId)` |
| `CountryContextService` | ✅ Operativo | Cache 30min, `getConfigBySiteId()` / `getConfigByCountry()` |
| `nv_accounts` columnas i18n | ✅ Migradas | `country`, `currency`, `mp_site_id`, `seller_fiscal_*` |
| `clients` (backend) columnas i18n | ✅ Migradas | `country`, `locale`, `timezone` |

### 2.2 Lo que FALTA ❌

| Componente | Gap | Impacto |
|-----------|-----|---------|
| `country_configs` | Sin `fiscal_id_label`, `fiscal_id_regex`, `personal_id_label`, etc. | FE no puede adaptar formulario |
| Catálogo subdivisiones | No existe tabla ni seed | 24 provincias AR están en el JSX |
| Catálogo fiscal categories | No existe tabla ni seed | 4 categorías AFIP están en el controller |
| Step8ClientData.tsx | 100% hardcodeado AR | FE no soporta otros países |
| `onboarding.controller.ts` | Valida solo CUIT 11 dígitos, persona_type AR, condicion_iva AR | Backend rechaza datos válidos de otros países |
| `onboarding.service.ts` | Persiste `cuit_cuil` como campo fijo | Nombre de campo incorrecto para otros países |
| `PlatformMercadoPagoService` | `assertMpSiteIsMLA()` + `currency_id: 'ARS'` hardcodeados | Bloquea token no-AR, cobra solo en ARS |
| `SubscriptionsService` | `getBlueDollarRate()` + columnas `*_ars` | Repricing solo funciona para ARS |
| Tabla `subscriptions` | Sin columnas `currency`, `country_id` | No sabe en qué moneda se cobra |
| MP tokens | Solo 1 token (MLA) | Necesita 1 token por site |
| Endpoint start-builder | Sin captcha ni rate limit | Vulnerable a spam/abuse |

---

## 3. Validaciones por País — Referencia Completa

### 3.1 Identificación Fiscal (Tax ID)

| País | Nombre | Regex (solo dígitos normalizados) | Prefijos válidos | Dígito verificador | Placeholder |
|------|--------|-----------------------------------|-------------------|-------------------|-------------|
| 🇦🇷 AR | CUIT/CUIL | `^\d{11}$` | 20,23,24,25,26,27 (PF) / 30,33,34 (PJ) | Mod 11, pesos `[5,4,3,2,7,6,5,4,3,2]` | `20-12345678-9` |
| 🇨🇱 CL | RUT | `^\d{7,8}[\dkK]$` | Ninguno fijo | Mod 11 cíclico `[2,3,4,5,6,7]`, 11→0, 10→K | `12.345.678-5` |
| 🇲🇽 MX | RFC | `^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$` | 4 letras=PF, 3 letras=PM | Homoclave (no verificable públicamente) | `XAXX010101000` |
| 🇨🇴 CO | NIT | `^\d{9,10}$` | Ninguno fijo | Mod 11, pesos `[41,37,29,23,19,17,13,7,3]` | `900.123.456-7` |
| 🇺🇾 UY | RUT | `^\d{12}$` | Ninguno fijo | Mod 11, pesos `[4,3,2,9,8,7,6,5,4,3,2]` | `211234567890` |
| 🇵🇪 PE | RUC | `^\d{11}$` | 10 (PF), 15,17,20 (PJ) | Mod 11, pesos `[5,4,3,2,7,6,5,4,3,2]` | `20123456789` |

### 3.2 Algoritmo Dígito Verificador — Pseudocódigo

```
FUNCIÓN verificarMod11(número: string, pesos: int[], moduloK: boolean = false):
  dígitos = número[0..n-2].map(toInt)
  dvEsperado = número[n-1]  // último caracter
  
  suma = 0
  PARA i = 0 HASTA dígitos.length - 1:
    suma += dígitos[i] * pesos[i]
  
  resto = 11 - (suma % 11)
  
  SI moduloK:    // Solo Chile
    SI resto == 11 → dv = '0'
    SI resto == 10 → dv = 'K'
    SINO → dv = str(resto)
  SINO:           // AR, CO, UY, PE
    SI resto == 11 → dv = '0'
    SI resto == 10 → dv = '0'  // varía por país
    SINO → dv = str(resto)
  
  RETORNAR dv == dvEsperado.toUpperCase()
```

### 3.3 Identificación Personal (Document ID)

| País | Nombre | Regex | Longitud | Nota |
|------|--------|-------|----------|------|
| 🇦🇷 AR | DNI | `^\d{7,8}$` | 7-8 dígitos | Sin dígito verificador |
| 🇨🇱 CL | RUN | `^\d{7,8}[\dkK]$` | 8-9 chars | **Mismo formato que RUT** |
| 🇲🇽 MX | CURP | `^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d$` | 18 chars | Incluye sexo, entidad, check digit |
| 🇨🇴 CO | CC | `^\d{6,10}$` | 6-10 dígitos | Cédula de Ciudadanía |
| 🇺🇾 UY | CI | `^\d{7,8}$` | 7-8 dígitos | Cédula de Identidad |
| 🇵🇪 PE | DNI | `^\d{8}$` | 8 dígitos exactos | Documento Nacional de Identidad |

### 3.4 Categorías Fiscales por País

| País | Persona Física | Persona Jurídica | Categorías fiscales (equivalentes a `condicion_iva`) |
|------|---------------|------------------|------------------------------------------------------|
| 🇦🇷 AR | Persona Física | Persona Jurídica (SRL/SA/SAS) | Monotributista, Responsable Inscripto, Exento, No Responsable |
| 🇨🇱 CL | Persona Natural | Persona Jurídica (SpA/Ltda/SA) | Primera Categoría, ProPyme, Régimen 14 A/D/E |
| 🇲🇽 MX | Persona Física | Persona Moral (SA de CV/SAPI) | RESICO (Simplificado), 612 (Actividades Empresariales), 601 (General de Ley), 625 (Asalariados) |
| 🇨🇴 CO | Persona Natural | Persona Jurídica (SAS/Ltda) | Responsable de IVA, No Responsable de IVA, RST (Régimen Simple de Tributación) |
| 🇺🇾 UY | Persona Física | Persona Jurídica (SA/SRL/SAS) | IRAE, Monotributo, Literal E |
| 🇵🇪 PE | Persona Natural | Persona Jurídica (SAC/EIRL/SRL) | NRUS (Nuevo RUS), RER (Especial de Renta), RMT (MYPE Tributario), Régimen General |

### 3.5 Subdivisiones Administrativas

| País | Nombre | Cantidad | Label |
|------|--------|----------|-------|
| 🇦🇷 AR | Provincias | 24 | Provincia |
| 🇨🇱 CL | Regiones | 16 | Región |
| 🇲🇽 MX | Estados | 32 | Estado |
| 🇨🇴 CO | Departamentos | 33 | Departamento |
| 🇺🇾 UY | Departamentos | 19 | Departamento |
| 🇵🇪 PE | Departamentos | 25 | Departamento |

**Listas completas en Anexo A (final del documento).**

### 3.6 Teléfonos

| País | Prefijo | Formato | Regex (normalizado sin prefijo) | Largo total |
|------|---------|---------|----------------------------------|-------------|
| 🇦🇷 AR | +54 | +54 9 XX XXXX-XXXX | `^\d{10}$` (sin 0 ni 15) | 10 dígitos |
| 🇨🇱 CL | +56 | +56 9 XXXX XXXX | `^\d{9}$` | 9 dígitos |
| 🇲🇽 MX | +52 | +52 XX XXXX XXXX | `^\d{10}$` | 10 dígitos |
| 🇨🇴 CO | +57 | +57 3XX XXX XXXX | `^\d{10}$` | 10 dígitos |
| 🇺🇾 UY | +598 | +598 9X XXX XXX | `^\d{8}$` (celular) | 8 dígitos |
| 🇵🇪 PE | +51 | +51 9XX XXX XXX | `^\d{9}$` | 9 dígitos |

---

## 4. Diseño de DB: Migraciones Requeridas

### 4.1 Migración: Ampliar `country_configs` — `ADMIN_080_country_configs_onboarding_fields`

```sql
-- Agrega campos para onboarding dinámico
ALTER TABLE country_configs
  ADD COLUMN IF NOT EXISTS fiscal_id_label        TEXT NOT NULL DEFAULT 'Tax ID',
  ADD COLUMN IF NOT EXISTS fiscal_id_regex        TEXT NOT NULL DEFAULT '^\d+$',
  ADD COLUMN IF NOT EXISTS fiscal_id_mask          TEXT,  -- ej: "XX-XXXXXXXX-X" para mostrar en placeholder
  ADD COLUMN IF NOT EXISTS fiscal_id_check_digit   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS personal_id_label       TEXT NOT NULL DEFAULT 'Document ID',
  ADD COLUMN IF NOT EXISTS personal_id_regex       TEXT NOT NULL DEFAULT '^\d+$',
  ADD COLUMN IF NOT EXISTS phone_prefix            TEXT NOT NULL DEFAULT '+1',
  ADD COLUMN IF NOT EXISTS phone_regex             TEXT NOT NULL DEFAULT '^\d{7,15}$',
  ADD COLUMN IF NOT EXISTS subdivision_label       TEXT NOT NULL DEFAULT 'State',
  ADD COLUMN IF NOT EXISTS persona_natural_label   TEXT NOT NULL DEFAULT 'Persona Natural',
  ADD COLUMN IF NOT EXISTS persona_juridica_label  TEXT NOT NULL DEFAULT 'Persona Jurídica';

-- Seed para cada país
UPDATE country_configs SET
  fiscal_id_label = 'CUIT/CUIL',
  fiscal_id_regex = '^\d{11}$',
  fiscal_id_mask = 'XX-XXXXXXXX-X',
  fiscal_id_check_digit = true,
  personal_id_label = 'DNI',
  personal_id_regex = '^\d{7,8}$',
  phone_prefix = '+54',
  phone_regex = '^\d{10}$',
  subdivision_label = 'Provincia',
  persona_natural_label = 'Persona Física',
  persona_juridica_label = 'Persona Jurídica'
WHERE site_id = 'MLA';

UPDATE country_configs SET
  fiscal_id_label = 'RUT',
  fiscal_id_regex = '^\d{7,8}[\dkK]$',
  fiscal_id_mask = 'XX.XXX.XXX-X',
  fiscal_id_check_digit = true,
  personal_id_label = 'RUN',
  personal_id_regex = '^\d{7,8}[\dkK]$',
  phone_prefix = '+56',
  phone_regex = '^\d{9}$',
  subdivision_label = 'Región',
  persona_natural_label = 'Persona Natural',
  persona_juridica_label = 'Persona Jurídica'
WHERE site_id = 'MLC';

UPDATE country_configs SET
  fiscal_id_label = 'RFC',
  fiscal_id_regex = '^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$',
  fiscal_id_mask = 'XXXX-XXXXXX-XXX',
  fiscal_id_check_digit = false,
  personal_id_label = 'CURP',
  personal_id_regex = '^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d$',
  phone_prefix = '+52',
  phone_regex = '^\d{10}$',
  subdivision_label = 'Estado',
  persona_natural_label = 'Persona Física',
  persona_juridica_label = 'Persona Moral'
WHERE site_id = 'MLM';

UPDATE country_configs SET
  fiscal_id_label = 'NIT',
  fiscal_id_regex = '^\d{9,10}$',
  fiscal_id_mask = 'XXX.XXX.XXX-X',
  fiscal_id_check_digit = true,
  personal_id_label = 'Cédula de Ciudadanía',
  personal_id_regex = '^\d{6,10}$',
  phone_prefix = '+57',
  phone_regex = '^\d{10}$',
  subdivision_label = 'Departamento',
  persona_natural_label = 'Persona Natural',
  persona_juridica_label = 'Persona Jurídica'
WHERE site_id = 'MCO';

UPDATE country_configs SET
  fiscal_id_label = 'RUT',
  fiscal_id_regex = '^\d{12}$',
  fiscal_id_mask = 'XXXXXXXXXXXX',
  fiscal_id_check_digit = true,
  personal_id_label = 'Cédula de Identidad',
  personal_id_regex = '^\d{7,8}$',
  phone_prefix = '+598',
  phone_regex = '^\d{8}$',
  subdivision_label = 'Departamento',
  persona_natural_label = 'Persona Física',
  persona_juridica_label = 'Persona Jurídica'
WHERE site_id = 'MLU';

UPDATE country_configs SET
  fiscal_id_label = 'RUC',
  fiscal_id_regex = '^\d{11}$',
  fiscal_id_mask = 'XXXXXXXXXXX',
  fiscal_id_check_digit = true,
  personal_id_label = 'DNI',
  personal_id_regex = '^\d{8}$',
  phone_prefix = '+51',
  phone_regex = '^\d{9}$',
  subdivision_label = 'Departamento',
  persona_natural_label = 'Persona Natural',
  persona_juridica_label = 'Persona Jurídica'
WHERE site_id = 'MPE';
```

### 4.2 Migración: Crear `country_subdivisions` — `ADMIN_081_country_subdivisions`

```sql
CREATE TABLE IF NOT EXISTS country_subdivisions (
  id          SERIAL PRIMARY KEY,
  country_id  TEXT NOT NULL,            -- AR, CL, MX, CO, UY, PE
  code        TEXT NOT NULL,            -- código ISO 3166-2 o simplificado
  name        TEXT NOT NULL,            -- nombre completo
  sort_order  SMALLINT NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(country_id, code)
);

CREATE INDEX idx_country_subdivisions_country ON country_subdivisions(country_id);

-- Seed Argentina (24 provincias)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('AR', 'CABA', 'Ciudad Autónoma de Buenos Aires', 1),
('AR', 'BA', 'Buenos Aires', 2),
('AR', 'CA', 'Catamarca', 3),
('AR', 'CH', 'Chaco', 4),
('AR', 'CT', 'Chubut', 5),
('AR', 'CB', 'Córdoba', 6),
('AR', 'CR', 'Corrientes', 7),
('AR', 'ER', 'Entre Ríos', 8),
('AR', 'FO', 'Formosa', 9),
('AR', 'JY', 'Jujuy', 10),
('AR', 'LP', 'La Pampa', 11),
('AR', 'LR', 'La Rioja', 12),
('AR', 'MZ', 'Mendoza', 13),
('AR', 'MI', 'Misiones', 14),
('AR', 'NQ', 'Neuquén', 15),
('AR', 'RN', 'Río Negro', 16),
('AR', 'SA', 'Salta', 17),
('AR', 'SJ', 'San Juan', 18),
('AR', 'SL', 'San Luis', 19),
('AR', 'SC', 'Santa Cruz', 20),
('AR', 'SF', 'Santa Fe', 21),
('AR', 'SE', 'Santiago del Estero', 22),
('AR', 'TF', 'Tierra del Fuego', 23),
('AR', 'TU', 'Tucumán', 24);

-- Seed Chile (16 regiones)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('CL', 'AP', 'Arica y Parinacota', 1),
('CL', 'TA', 'Tarapacá', 2),
('CL', 'AN', 'Antofagasta', 3),
('CL', 'AT', 'Atacama', 4),
('CL', 'CO', 'Coquimbo', 5),
('CL', 'VS', 'Valparaíso', 6),
('CL', 'RM', 'Metropolitana de Santiago', 7),
('CL', 'LI', 'O''Higgins', 8),
('CL', 'ML', 'Maule', 9),
('CL', 'NB', 'Ñuble', 10),
('CL', 'BI', 'Biobío', 11),
('CL', 'AR', 'La Araucanía', 12),
('CL', 'LR', 'Los Ríos', 13),
('CL', 'LL', 'Los Lagos', 14),
('CL', 'AI', 'Aysén', 15),
('CL', 'MA', 'Magallanes', 16);

-- Seed México (32 estados)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('MX', 'AGU', 'Aguascalientes', 1),
('MX', 'BCN', 'Baja California', 2),
('MX', 'BCS', 'Baja California Sur', 3),
('MX', 'CAM', 'Campeche', 4),
('MX', 'CHP', 'Chiapas', 5),
('MX', 'CHH', 'Chihuahua', 6),
('MX', 'COA', 'Coahuila', 7),
('MX', 'COL', 'Colima', 8),
('MX', 'CMX', 'Ciudad de México', 9),
('MX', 'DUR', 'Durango', 10),
('MX', 'GUA', 'Guanajuato', 11),
('MX', 'GRO', 'Guerrero', 12),
('MX', 'HID', 'Hidalgo', 13),
('MX', 'JAL', 'Jalisco', 14),
('MX', 'MEX', 'Estado de México', 15),
('MX', 'MIC', 'Michoacán', 16),
('MX', 'MOR', 'Morelos', 17),
('MX', 'NAY', 'Nayarit', 18),
('MX', 'NLE', 'Nuevo León', 19),
('MX', 'OAX', 'Oaxaca', 20),
('MX', 'PUE', 'Puebla', 21),
('MX', 'QUE', 'Querétaro', 22),
('MX', 'ROO', 'Quintana Roo', 23),
('MX', 'SLP', 'San Luis Potosí', 24),
('MX', 'SIN', 'Sinaloa', 25),
('MX', 'SON', 'Sonora', 26),
('MX', 'TAB', 'Tabasco', 27),
('MX', 'TAM', 'Tamaulipas', 28),
('MX', 'TLA', 'Tlaxcala', 29),
('MX', 'VER', 'Veracruz', 30),
('MX', 'YUC', 'Yucatán', 31),
('MX', 'ZAC', 'Zacatecas', 32);

-- Seed Colombia (33 departamentos)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('CO', 'AMA', 'Amazonas', 1),
('CO', 'ANT', 'Antioquia', 2),
('CO', 'ARA', 'Arauca', 3),
('CO', 'ATL', 'Atlántico', 4),
('CO', 'BOL', 'Bolívar', 5),
('CO', 'BOY', 'Boyacá', 6),
('CO', 'CAL', 'Caldas', 7),
('CO', 'CAQ', 'Caquetá', 8),
('CO', 'CAS', 'Casanare', 9),
('CO', 'CAU', 'Cauca', 10),
('CO', 'CES', 'Cesar', 11),
('CO', 'CHO', 'Chocó', 12),
('CO', 'COR', 'Córdoba', 13),
('CO', 'CUN', 'Cundinamarca', 14),
('CO', 'DC', 'Bogotá D.C.', 15),
('CO', 'GUA', 'Guainía', 16),
('CO', 'GUV', 'Guaviare', 17),
('CO', 'HUI', 'Huila', 18),
('CO', 'LAG', 'La Guajira', 19),
('CO', 'MAG', 'Magdalena', 20),
('CO', 'MET', 'Meta', 21),
('CO', 'NAR', 'Nariño', 22),
('CO', 'NSA', 'Norte de Santander', 23),
('CO', 'PUT', 'Putumayo', 24),
('CO', 'QUI', 'Quindío', 25),
('CO', 'RIS', 'Risaralda', 26),
('CO', 'SAP', 'San Andrés y Providencia', 27),
('CO', 'SAN', 'Santander', 28),
('CO', 'SUC', 'Sucre', 29),
('CO', 'TOL', 'Tolima', 30),
('CO', 'VAC', 'Valle del Cauca', 31),
('CO', 'VAU', 'Vaupés', 32),
('CO', 'VID', 'Vichada', 33);

-- Seed Uruguay (19 departamentos)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('UY', 'AR', 'Artigas', 1),
('UY', 'CA', 'Canelones', 2),
('UY', 'CL', 'Cerro Largo', 3),
('UY', 'CO', 'Colonia', 4),
('UY', 'DU', 'Durazno', 5),
('UY', 'FS', 'Flores', 6),
('UY', 'FD', 'Florida', 7),
('UY', 'LA', 'Lavalleja', 8),
('UY', 'MA', 'Maldonado', 9),
('UY', 'MO', 'Montevideo', 10),
('UY', 'PA', 'Paysandú', 11),
('UY', 'RN', 'Río Negro', 12),
('UY', 'RV', 'Rivera', 13),
('UY', 'RO', 'Rocha', 14),
('UY', 'SA', 'Salto', 15),
('UY', 'SJ', 'San José', 16),
('UY', 'SO', 'Soriano', 17),
('UY', 'TA', 'Tacuarembó', 18),
('UY', 'TT', 'Treinta y Tres', 19);

-- Seed Perú (25 departamentos)
INSERT INTO country_subdivisions (country_id, code, name, sort_order) VALUES
('PE', 'AMA', 'Amazonas', 1),
('PE', 'ANC', 'Áncash', 2),
('PE', 'APU', 'Apurímac', 3),
('PE', 'ARE', 'Arequipa', 4),
('PE', 'AYA', 'Ayacucho', 5),
('PE', 'CAJ', 'Cajamarca', 6),
('PE', 'CUS', 'Cusco', 7),
('PE', 'HUV', 'Huancavelica', 8),
('PE', 'HUC', 'Huánuco', 9),
('PE', 'ICA', 'Ica', 10),
('PE', 'JUN', 'Junín', 11),
('PE', 'LAL', 'La Libertad', 12),
('PE', 'LAM', 'Lambayeque', 13),
('PE', 'LIM', 'Lima', 14),
('PE', 'LOR', 'Loreto', 15),
('PE', 'MDD', 'Madre de Dios', 16),
('PE', 'MOQ', 'Moquegua', 17),
('PE', 'PAS', 'Pasco', 18),
('PE', 'PIU', 'Piura', 19),
('PE', 'PUN', 'Puno', 20),
('PE', 'SAM', 'San Martín', 21),
('PE', 'TAC', 'Tacna', 22),
('PE', 'TUM', 'Tumbes', 23),
('PE', 'UCA', 'Ucayali', 24),
('PE', 'CAL', 'Callao', 25);

-- RLS
ALTER TABLE country_subdivisions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subdivisions_public_read" ON country_subdivisions FOR SELECT USING (true);
CREATE POLICY "subdivisions_service_role" ON country_subdivisions FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
```

### 4.3 Migración: Crear `country_fiscal_categories` — `ADMIN_082_country_fiscal_categories`

```sql
CREATE TABLE IF NOT EXISTS country_fiscal_categories (
  id          SERIAL PRIMARY KEY,
  country_id  TEXT NOT NULL,
  code        TEXT NOT NULL,            -- clave interna (ej: 'monotributista')
  label       TEXT NOT NULL,            -- display (ej: 'Monotributista')
  description TEXT,                     -- ayuda contextual
  sort_order  SMALLINT NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT true,
  UNIQUE(country_id, code)
);

CREATE INDEX idx_country_fiscal_categories_country ON country_fiscal_categories(country_id);

-- Argentina
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('AR', 'monotributista', 'Monotributista', 1),
('AR', 'responsable_inscripto', 'Responsable Inscripto', 2),
('AR', 'exento', 'Exento', 3),
('AR', 'no_responsable', 'No Responsable', 4);

-- Chile
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('CL', 'primera_categoria', 'Primera Categoría', 1),
('CL', 'propyme', 'ProPyme (Régimen 14D #3)', 2),
('CL', 'regimen_14a', 'Régimen General (14A)', 3),
('CL', 'regimen_14d', 'Régimen ProPyme (14D)', 4),
('CL', 'regimen_14e', 'Régimen Transparencia (14E)', 5);

-- México
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('MX', 'resico', 'RESICO (Régimen Simplificado de Confianza)', 1),
('MX', 'regimen_612', '612 - Actividades Empresariales y Profesionales', 2),
('MX', 'regimen_601', '601 - General de Ley de Personas Morales', 3),
('MX', 'regimen_625', '625 - Régimen de Actividades Empresariales con Ingresos a través de Plataformas', 4),
('MX', 'regimen_626', '626 - Régimen Simplificado de Confianza (Persona Moral)', 5);

-- Colombia
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('CO', 'responsable_iva', 'Responsable de IVA', 1),
('CO', 'no_responsable_iva', 'No Responsable de IVA', 2),
('CO', 'rst', 'RST (Régimen Simple de Tributación)', 3);

-- Uruguay
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('UY', 'irae', 'IRAE (Impuesto a la Renta)', 1),
('UY', 'monotributo', 'Monotributo', 2),
('UY', 'literal_e', 'Literal E (Pequeña empresa)', 3);

-- Perú
INSERT INTO country_fiscal_categories (country_id, code, label, sort_order) VALUES
('PE', 'nrus', 'NRUS (Nuevo RUS)', 1),
('PE', 'rer', 'RER (Régimen Especial de Renta)', 2),
('PE', 'rmt', 'RMT (Régimen MYPE Tributario)', 3),
('PE', 'regimen_general', 'Régimen General', 4);

-- RLS
ALTER TABLE country_fiscal_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fiscal_cats_public_read" ON country_fiscal_categories FOR SELECT USING (true);
CREATE POLICY "fiscal_cats_service_role" ON country_fiscal_categories FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
```

### 4.4 Migración: Generalizar `nv_accounts` — `ADMIN_083_nv_accounts_generic_fiscal`

```sql
-- Campos genéricos (multi-país) que actúan como alias de los argentinos actuales
-- No eliminamos los campos argentinos existentes para backward compatibility;
-- en su lugar, creamos campos genéricos y mapeamos los existentes

ALTER TABLE nv_accounts
  ADD COLUMN IF NOT EXISTS fiscal_id            TEXT,     -- valor normalizado del tax ID
  ADD COLUMN IF NOT EXISTS fiscal_id_type       TEXT,     -- 'CUIT','RUT','RFC','NIT','RUC'
  ADD COLUMN IF NOT EXISTS personal_id          TEXT,     -- valor normalizado del doc ID
  ADD COLUMN IF NOT EXISTS personal_id_type     TEXT,     -- 'DNI','RUN','CURP','CC','CI'
  ADD COLUMN IF NOT EXISTS fiscal_category      TEXT,     -- código de country_fiscal_categories
  ADD COLUMN IF NOT EXISTS subdivision_code     TEXT,     -- código de country_subdivisions
  ADD COLUMN IF NOT EXISTS phone_full           TEXT;     -- teléfono con prefijo internacional

-- Migrar datos argentinos existentes a campos genéricos
UPDATE nv_accounts SET
  fiscal_id = cuit_cuil,
  fiscal_id_type = 'CUIT',
  fiscal_category = condicion_iva,
  subdivision_code = provincia
WHERE cuit_cuil IS NOT NULL AND country IS NULL OR country = 'AR';

-- (los campos originales cuit_cuil, condicion_iva, provincia se mantienen por ahora
--  para no romper código existente; se deprecan gradualmente)

COMMENT ON COLUMN nv_accounts.fiscal_id IS 'Generic tax ID (CUIT/RUT/RFC/NIT/RUC) - replaces cuit_cuil';
COMMENT ON COLUMN nv_accounts.fiscal_category IS 'Generic fiscal category code - replaces condicion_iva';
COMMENT ON COLUMN nv_accounts.subdivision_code IS 'Generic admin subdivision code - replaces provincia';

CREATE INDEX IF NOT EXISTS idx_nv_accounts_fiscal_id ON nv_accounts(fiscal_id);
```

### 4.5 Migración: Agregar `currency` y `country_id` a `subscriptions` — `ADMIN_084_subscriptions_multicurrency`

```sql
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS currency      TEXT NOT NULL DEFAULT 'ARS',
  ADD COLUMN IF NOT EXISTS country_id    TEXT NOT NULL DEFAULT 'AR',
  -- Columnas genéricas de precio local (aliases de las _ars)
  ADD COLUMN IF NOT EXISTS initial_price_local   NUMERIC,
  ADD COLUMN IF NOT EXISTS original_price_local  NUMERIC,
  ADD COLUMN IF NOT EXISTS last_charged_local    NUMERIC,
  ADD COLUMN IF NOT EXISTS next_estimated_local  NUMERIC;

-- Migrar datos existentes (todos son ARS)
UPDATE subscriptions SET
  initial_price_local = initial_price_ars,
  original_price_local = original_price_ars,
  last_charged_local = last_charged_ars,
  next_estimated_local = next_estimated_ars
WHERE initial_price_ars IS NOT NULL;

COMMENT ON COLUMN subscriptions.currency IS 'ISO 4217 currency code (ARS, CLP, MXN, etc)';
COMMENT ON COLUMN subscriptions.country_id IS 'ISO 3166-1 alpha-2 country code';
COMMENT ON COLUMN subscriptions.initial_price_local IS 'Price in local currency at creation - replaces initial_price_ars';

CREATE INDEX IF NOT EXISTS idx_subscriptions_country ON subscriptions(country_id);
```

### 4.6 Migración Backend: `BACKEND_048_clients_generic_fiscal`

```sql
-- En la DB de Backend (multicliente), sincronizar estructura genérica
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS fiscal_id         TEXT,
  ADD COLUMN IF NOT EXISTS fiscal_id_type    TEXT,
  ADD COLUMN IF NOT EXISTS fiscal_category   TEXT,
  ADD COLUMN IF NOT EXISTS subdivision_code  TEXT;

-- Migrar datos AR existentes
UPDATE clients SET
  fiscal_id = cuit_cuil,
  fiscal_id_type = 'CUIT',
  fiscal_category = condicion_iva,
  subdivision_code = provincia
WHERE cuit_cuil IS NOT NULL;
```

### 4.7 Resumen Impacto DB

| Tabla | Acción | Columnas nuevas | Risk |
|-------|--------|-----------------|------|
| `country_configs` | ALTER + UPDATE | 11 columnas | Bajo — no rompe nada existente |
| `country_subdivisions` | CREATE TABLE | Nueva tabla (149 filas seed) | Bajo |
| `country_fiscal_categories` | CREATE TABLE | Nueva tabla (~21 filas seed) | Bajo |
| `nv_accounts` | ALTER (7 cols) + UPDATE | Campos genéricos + migración datos AR | Medio — doble-write durante transición |
| `subscriptions` | ALTER (6 cols) + UPDATE | currency + country + precios genéricos | Medio — repricing debe usar nuevos campos |
| `clients` (backend) | ALTER (4 cols) + UPDATE | Campos genéricos | Bajo |

---

## 5. Cambios en Backend (API)

### 5.1 Nuevo endpoint: `GET /onboarding/country-config/:countryId`

Devuelve toda la configuración de onboarding para un país:

```typescript
// Response
{
  country_id: 'AR',
  site_id: 'MLA',
  currency_id: 'ARS',
  locale: 'es-AR',
  // Campos de onboarding
  fiscal_id_label: 'CUIT/CUIL',
  fiscal_id_regex: '^\d{11}$',
  fiscal_id_mask: 'XX-XXXXXXXX-X',
  fiscal_id_check_digit: true,
  personal_id_label: 'DNI',
  personal_id_regex: '^\d{7,8}$',
  phone_prefix: '+54',
  phone_regex: '^\d{10}$',
  subdivision_label: 'Provincia',
  persona_natural_label: 'Persona Física',
  persona_juridica_label: 'Persona Jurídica',
  // Catálogos
  subdivisions: [{ code: 'CABA', name: 'Ciudad Autónoma de Buenos Aires' }, ...],
  fiscal_categories: [{ code: 'monotributista', label: 'Monotributista' }, ...],
}
```

### 5.2 Refactorizar `POST /onboarding/business-info`

**Antes (hardcodeado AR):**
```typescript
if (!/^\d{11}$/.test(body.cuit_cuil)) throw 400;
if (!['fisica','juridica'].includes(body.persona_type)) throw 400;
if (!['monotributista','responsable_inscripto','exento','no_responsable']
    .includes(body.condicion_iva)) throw 400;
```

**Después (dinámico por país):**
```typescript
// 1. Obtener config del país de la cuenta
const account = await getAccount(accountId);
const countryConfig = await countryContext.getConfigByCountry(account.country);

// 2. Validar fiscal_id con regex del país
const fiscalRegex = new RegExp(countryConfig.fiscal_id_regex);
if (!fiscalRegex.test(body.fiscal_id)) {
  throw new BadRequestException(`${countryConfig.fiscal_id_label} inválido`);
}

// 3. Si el país tiene check digit, validar
if (countryConfig.fiscal_id_check_digit) {
  if (!this.validateCheckDigit(account.country, body.fiscal_id)) {
    throw new BadRequestException(`Dígito verificador de ${countryConfig.fiscal_id_label} inválido`);
  }
}

// 4. Validar persona_type (genérico: natural/juridica)
if (body.persona_type && !['natural', 'juridica'].includes(body.persona_type)) {
  throw new BadRequestException('Tipo de persona inválido');
}

// 5. Validar fiscal_category contra catálogo del país
if (body.fiscal_category) {
  const validCats = await this.getFiscalCategories(account.country);
  if (!validCats.find(c => c.code === body.fiscal_category)) {
    throw new BadRequestException('Categoría fiscal inválida para este país');
  }
}

// 6. Validar subdivision contra catálogo del país
if (body.subdivision_code) {
  const validSubs = await this.getSubdivisions(account.country);
  if (!validSubs.find(s => s.code === body.subdivision_code)) {
    throw new BadRequestException('Subdivisión inválida para este país');
  }
}
```

### 5.3 Nuevo: `FiscalIdValidatorService`

Centraliza la validación de dígitos verificadores:

```typescript
@Injectable()
export class FiscalIdValidatorService {
  
  validateCheckDigit(countryId: string, fiscalId: string): boolean {
    const normalized = fiscalId.replace(/[^0-9kK]/gi, '');
    switch (countryId) {
      case 'AR': return this.validateCuitAR(normalized);
      case 'CL': return this.validateRutCL(normalized);
      case 'CO': return this.validateNitCO(normalized);
      case 'UY': return this.validateRutUY(normalized);
      case 'PE': return this.validateRucPE(normalized);
      case 'MX': return true; // RFC no tiene check digit público
      default: return true;
    }
  }

  private mod11(digits: number[], weights: number[]): number {
    const sum = digits.reduce((acc, d, i) => acc + d * weights[i], 0);
    const rem = 11 - (sum % 11);
    return rem === 11 ? 0 : rem === 10 ? 0 : rem;
  }

  private validateCuitAR(cuit: string): boolean {
    if (cuit.length !== 11) return false;
    const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    const digits = cuit.slice(0, 10).split('').map(Number);
    const expected = parseInt(cuit[10]);
    return this.mod11(digits, weights) === expected;
  }

  private validateRutCL(rut: string): boolean {
    if (rut.length < 8 || rut.length > 9) return false;
    const body = rut.slice(0, -1).split('').map(Number);
    const dv = rut.slice(-1).toUpperCase();
    let sum = 0, mul = 2;
    for (let i = body.length - 1; i >= 0; i--) {
      sum += body[i] * mul;
      mul = mul === 7 ? 2 : mul + 1;
    }
    const rem = 11 - (sum % 11);
    const expected = rem === 11 ? '0' : rem === 10 ? 'K' : String(rem);
    return dv === expected;
  }

  private validateNitCO(nit: string): boolean {
    if (nit.length < 9 || nit.length > 10) return false;
    const padded = nit.padStart(10, '0');
    const weights = [41, 37, 29, 23, 19, 17, 13, 7, 3];
    const digits = padded.slice(0, 9).split('').map(Number);
    const expected = parseInt(padded[9]);
    const sum = digits.reduce((acc, d, i) => acc + d * weights[i], 0);
    const rem = sum % 11;
    const dv = rem <= 1 ? 0 : 11 - rem;
    return dv === expected;
  }

  private validateRutUY(rut: string): boolean {
    if (rut.length !== 12) return false;
    const weights = [4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const digits = rut.slice(0, 11).split('').map(Number);
    const expected = parseInt(rut[11]);
    return this.mod11(digits, weights) === expected;
  }

  private validateRucPE(ruc: string): boolean {
    if (ruc.length !== 11) return false;
    const weights = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    const digits = ruc.slice(0, 10).split('').map(Number);
    const expected = parseInt(ruc[10]);
    return this.mod11(digits, weights) === expected;
  }
}
```

### 5.4 Nuevo payload genérico para `POST /onboarding/business-info`

```typescript
// Antes (AR-only)
{
  business_name, cuit_cuil, fiscal_address, phone, billing_email,
  persona_type, razon_social, condicion_iva, provincia
}

// Después (multi-país)
{
  business_name: string,            // Nombre comercial
  fiscal_id: string,                // CUIT/RUT/RFC/NIT/RUC
  fiscal_address: string,           // Dirección fiscal
  phone: string,                    // Teléfono (con o sin prefijo)
  billing_email: string,            // Email de facturación
  persona_type: 'natural'|'juridica',  // Genérico (ya no fisica/juridica AR)
  legal_name?: string,              // Razón social (reemplaza razon_social)
  fiscal_category?: string,         // Código de country_fiscal_categories
  subdivision_code?: string,        // Código de country_subdivisions
}
```

**Backward compatibility:** Aceptar TAMBIÉN los campos viejos (`cuit_cuil`, `razon_social`, `condicion_iva`, `provincia`) y mapearlos internamente a los genéricos durante la transición.

---

## 6. Cambios en Frontend (Admin)

### 6.1 Refactorizar `Step8ClientData.tsx`

**Estrategia:** El componente carga la configuración del país al montar y renderiza los campos dinámicamente.

```
useEffect on mount:
  1. Detectar país de la cuenta (de builderState o context)
  2. fetch GET /onboarding/country-config/{countryId}
  3. Guardar en estado: { config, subdivisions, fiscalCategories }

Render:
  - Label fiscal ID → config.fiscal_id_label
  - Placeholder → config.fiscal_id_mask
  - Select subdivisiones → subdivisions[]
  - Select categorías → fiscalCategories[]
  - Prefijo tel → config.phone_prefix
  - Labels persona → config.persona_natural_label / config.persona_juridica_label
  - Validación fiscal → new RegExp(config.fiscal_id_regex)
```

### 6.2 Nuevo: `FiscalIdValidator.ts` (frontend)

Mirror del validador backend para feedback inmediato en el form:

```typescript
export function validateFiscalId(countryId: string, value: string): { valid: boolean; message?: string } {
  const normalized = value.replace(/[^0-9a-zA-Z]/gi, '');
  // Lógica de check digit per country (mismos algoritmos que backend)
  // Retorna { valid: true } o { valid: false, message: 'Dígito verificador inválido' }
}
```

### 6.3 Nuevo: `dniUtils.ts` → `identityDocUtils.ts`

Renombrar y generalizar:
- `isValidDni()` → `isValidPersonalId(countryId, value)`
- `resizeImage()` sigue igual (es genérica)
- Agregar validación de CURP (México) si es alfanumérico

### 6.4 Selector de país en el wizard

**Opción A (recomendada):** El país se detecta automáticamente del `mp_site_id` de la cuenta (que viene del OAuth de MP). No hace falta selector manual.

**Opción B:** Si el OAuth de MP aún no ocurrió en Step8, usar un campo `country` guardado en el draft al iniciar el builder (Step 1 o 2).

**Decisión necesaria del TL:** ¿Se asigna el país en `start-builder` (por IP geolocated) o se pide explícitamente en algún step anterior?

---

## 7. Suscripciones MP Multi-País

### 7.1 Problema actual

```
PlatformMercadoPagoService:
  - 1 token (PLATFORM_MP_ACCESS_TOKEN) → MLA (Argentina)
  - assertMpSiteIsMLA() bloquea si no es MLA
  - currency_id: 'ARS' hardcodeado
  
SubscriptionsService:
  - getBlueDollarRate() → solo USD→ARS
  - Columnas: *_ars (initial_price_ars, etc.)
  - Repricing: solo dólar blue
```

### 7.2 Diseño: Token Pool multi-site

**Cada site de MP requiere su propio access token.** La cuenta NovaVision platform debe estar registrada como marketplace en cada país.

```typescript
// Configuración por env vars:
PLATFORM_MP_ACCESS_TOKEN_MLA=APP_USR-xxx  // Argentina
PLATFORM_MP_ACCESS_TOKEN_MLC=APP_USR-xxx  // Chile
PLATFORM_MP_ACCESS_TOKEN_MLM=APP_USR-xxx  // México
PLATFORM_MP_ACCESS_TOKEN_MCO=APP_USR-xxx  // Colombia
PLATFORM_MP_ACCESS_TOKEN_MLU=APP_USR-xxx  // Uruguay
PLATFORM_MP_ACCESS_TOKEN_MPE=APP_USR-xxx  // Perú

// O bien en tabla:
// platform_mp_tokens(site_id PK, access_token TEXT ENCRYPTED, active BOOLEAN)
```

**Router de tokens:**
```typescript
class PlatformMercadoPagoService {
  private clients: Map<string, MercadoPagoConfig>; // site_id → config
  
  getMpClientForSite(siteId: string): MercadoPagoConfig {
    const client = this.clients.get(siteId);
    if (!client) throw new Error(`No MP token configured for site ${siteId}`);
    return client;
  }
}
```

### 7.3 Cambios en `createSubscription()`

```typescript
// Antes
async createSubscription(accountId, priceArs, payerEmail, ...) {
  const body = { ...currency_id: 'ARS', transaction_amount: priceArs };
  return this.preApproval.create({ body });
}

// Después
async createSubscription(accountId, priceLocal, payerEmail, siteId, currencyId, ...) {
  const mpClient = this.getMpClientForSite(siteId);
  const decimals = currencyId === 'CLP' || currencyId === 'COP' ? 0 : 2;
  const amount = decimals === 0 ? Math.ceil(priceLocal) : Number(priceLocal.toFixed(2));
  
  const preApproval = new PreApproval(mpClient);
  const body = { 
    ...
    currency_id: currencyId,
    transaction_amount: amount
  };
  return preApproval.create({ body });
}
```

### 7.4 Cambios en `createSubscriptionForAccount()`

```typescript
// Antes
const blueRate = await this.getBlueDollarRate();
const initialPriceArs = Math.ceil(planPriceUsd * blueRate);

// Después
const account = await this.getAccount(accountId);
const countryId = account.country || 'AR';
const countryConfig = await this.countryContext.getConfigByCountry(countryId);
const localRate = await this.fxService.getRate(countryId); // ya multi-país
const initialPriceLocal = countryConfig.decimals === 0
  ? Math.ceil(planPriceUsd * localRate)
  : Number((planPriceUsd * localRate).toFixed(2));
```

### 7.5 Cambios en `checkAndUpdatePrices()` (repricing)

```typescript
// Para cada suscripción activa:
const sub = subscriptions[i];
const newRate = await this.fxService.getRate(sub.country_id);
const newPriceLocal = sub.country_config?.decimals === 0 
  ? Math.ceil(sub.plan_price_usd * newRate) 
  : Number((sub.plan_price_usd * newRate).toFixed(2));

// Actualizar en MP con el client del site correcto
await this.platformMp.updateSubscriptionPrice(
  sub.mp_preapproval_id, 
  newPriceLocal, 
  sub.siteId, 
  sub.currency
);
```

### 7.6 Impacto en Facturación/Billing

- `plan_price_usd` sigue siendo la referencia en USD
- Las columnas `*_ars` se mantienen para suscripciones existentes (backward compat)
- Nuevas suscripciones usan `currency` + `*_local`
- Overage crons (billing.service.ts) necesitan saber la moneda de cada cuenta

---

## 8. 3 Fixes de Seguridad (Riesgos ALTOS)

### 8.1 S1: Tokens MP — Evaluación actualizada

**Hallazgo de la auditoría:** El `mp_access_token` **SÍ se encripta** vía RPC de Postgres `encrypt_mp_token` (usa `pgcrypto`). El `mp_public_key` está en texto plano pero **no es un secreto** (es una clave pública).

**Estado: ⚠️ MEDIO (no ALTO)**

**Acción recomendada:**
1. Verificar que la RPC `encrypt_mp_token` usa una clave de encriptación robusta (no hardcodeada en la función SQL)
2. Verificar que la clave de encriptación NO está en el código fuente — debe estar en env var del proyecto Supabase
3. Agregar log de auditoría cuando se accede/decripta el token
4. Documentar el flujo de encriptación/decriptación

**Acción manual del TL:** Revisar en Supabase Dashboard → SQL Editor:
```sql
-- Ver la implementación de encrypt_mp_token
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'encrypt_mp_token';
-- Verificar si usa una variable de entorno o clave hardcodeada
```

### 8.2 S2: CAPTCHA en `POST /onboarding/builder/start`

**Riesgo:** Endpoint público sin protección. Un bot puede crear miles de drafts.

**Implementación propuesta: Cloudflare Turnstile** (gratuito, privacy-friendly, no-Google)

**Backend:**
```typescript
// onboarding.controller.ts - start-builder endpoint
@Post('builder/start')
@AllowNoTenant()
async startBuilder(@Body() body: StartBuilderDto, @Ip() ip: string) {
  // 1. Validar Turnstile token
  if (!body.captcha_token) {
    throw new BadRequestException('captcha_token is required');
  }
  const captchaValid = await this.captchaService.verifyTurnstile(body.captcha_token, ip);
  if (!captchaValid) {
    throw new BadRequestException('Captcha verification failed');
  }
  
  // 2. Resto del flujo...
  return this.onboardingService.startDraftBuilder(body.email, body.slug);
}
```

**CaptchaService:**
```typescript
@Injectable()
export class CaptchaService {
  async verifyTurnstile(token: string, ip: string): Promise<boolean> {
    const secret = this.configService.get('TURNSTILE_SECRET_KEY');
    if (!secret) return true; // Skip en dev si no hay clave
    
    const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret, response: token, remoteip: ip }),
    });
    const data = await response.json();
    return data.success === true;
  }
}
```

**Frontend (Admin):**
```tsx
// En el componente de inicio de onboarding
import { Turnstile } from '@marsidev/react-turnstile'

<Turnstile 
  siteKey={import.meta.env.VITE_TURNSTILE_SITE_KEY}
  onSuccess={(token) => setCaptchaToken(token)}
/>
```

**Env vars nuevas:**
```env
# Backend
TURNSTILE_SECRET_KEY=0x...

# Frontend (Admin)
VITE_TURNSTILE_SITE_KEY=0x...
```

**Acción manual del TL:**
1. Crear cuenta Cloudflare (si no hay) y activar Turnstile
2. Crear un widget Turnstile tipo "Managed"
3. Obtener Site Key y Secret Key
4. Agregar a env vars en Railway (backend) y Netlify (admin)

### 8.3 S3: Rate Limiting en `POST /onboarding/builder/start`

**Implementación propuesta: ThrottlerGuard de NestJS**

```typescript
// Usar @nestjs/throttler (ya probablemente en package.json o fácil de agregar)

// En app.module.ts o onboarding.module.ts:
ThrottlerModule.forRoot([{
  name: 'builder-start',
  ttl: 60000,   // ventana de 1 minuto
  limit: 5,     // máximo 5 requests por IP
}]),

// En el controller:
@Post('builder/start')
@AllowNoTenant()
@Throttle({ 'builder-start': { ttl: 60000, limit: 5 } })
async startBuilder(@Body() body: StartBuilderDto) { ... }
```

**Rate limit adicional por email (en el service):**
```typescript
// En startDraftBuilder():
// Contar drafts recientes de este email
const { count } = await supabase
  .from('nv_accounts')
  .select('id', { count: 'exact' })
  .eq('email', email)
  .gte('created_at', new Date(Date.now() - 3600000).toISOString()); // última hora

if (count >= 3) {
  throw new TooManyRequestsException('Demasiados intentos. Intentá de nuevo en una hora.');
}
```

---

## 9. Impacto en PreApproval y Billing

### 9.1 PreApproval por país

| Aspecto | Antes (AR only) | Después (multi-país) |
|---------|-----------------|----------------------|
| Token MP | 1 token MLA | Pool de tokens por site |
| Currency | `'ARS'` hardcoded | `countryConfig.currency_id` |
| Tasa FX | `getBlueDollarRate()` | `fxService.getRate(countryId)` |
| Precio | `Math.ceil(usd * rate)` | Con decimales según país |
| Repricing | Solo ARS | Multi-moneda |
| DB columns | `*_ars` | `*_ars` (legacy) + `*_local` (new) |

### 9.2 Billing/Overage

- `billing.service.ts` usa `initial_price_ars` para calcular comisiones
- Debe migrar a `initial_price_local` + `currency` para cálculos correctos
- Los totales de facturación NovaVision siguen en USD (referencia interna)

### 9.3 Emails de suscripción

- Los emails de bienvenida, repricing, vencimiento muestran precios en ARS
- Debe usar `Intl.NumberFormat(locale, { style: 'currency', currency })` para formatear correctamente según país

---

## 10. Fases de Implementación

### Fase A — Catálogos y DB (Riesgo BAJO) — ~2 días

| Tarea | Repo | Archivos |
|-------|------|----------|
| A1. Migración ADMIN_080: ampliar country_configs | API | `migrations/admin/` |
| A2. Migración ADMIN_081: crear country_subdivisions | API | `migrations/admin/` |
| A3. Migración ADMIN_082: crear country_fiscal_categories | API | `migrations/admin/` |
| A4. Migración ADMIN_083: campos genéricos nv_accounts | API | `migrations/admin/` |
| A5. Migración ADMIN_084: multicurrency subscriptions | API | `migrations/admin/` |
| A6. Migración BACKEND_048: campos genéricos clients | API | `migrations/backend/` |
| A7. Actualizar CountryContextService (cachear nuevos campos) | API | `src/common/country-context.service.ts` |
| A8. Endpoint `GET /onboarding/country-config/:id` | API | `src/onboarding/onboarding.controller.ts` |
| **Ejecutar migraciones** | **Manual TL** | **Ambas DBs** |

### Fase B — Validación Backend (Riesgo MEDIO) — ~3 días

| Tarea | Repo | Archivos |
|-------|------|----------|
| B1. Crear FiscalIdValidatorService | API | `src/common/fiscal-id-validator.service.ts` |
| B2. Refactorizar business-info endpoint (validaciones dinámicas) | API | `src/onboarding/onboarding.controller.ts` |
| B3. Refactorizar saveBusinessInfo (doble-write campos genéricos) | API | `src/onboarding/onboarding.service.ts` |
| B4. Tests unitarios: validadores por los 6 países | API | `src/common/__tests__/fiscal-id-validator.spec.ts` |
| B5. Tests unitarios: business-info con payload multi-país | API | Tests de onboarding |
| B6. Backward compat: seguir aceptando payload viejo (cuit_cuil, etc.) | API | `src/onboarding/` |

### Fase C — Frontend Dinámico (Riesgo MEDIO) — ~3 días

| Tarea | Repo | Archivos |
|-------|------|----------|
| C1. Crear hook `useCountryConfig(countryId)` | Admin | `src/pages/BuilderWizard/hooks/` |
| C2. Crear `FiscalIdValidator.ts` (mirror de backend) | Admin | `src/pages/BuilderWizard/utils/` |
| C3. Refactorizar Step8ClientData.tsx — eliminar hardcodes | Admin | `src/pages/BuilderWizard/steps/` |
| C4. Renombrar dniUtils.ts → identityDocUtils.ts | Admin | `src/pages/BuilderWizard/utils/` |
| C5. Actualizar tour/ayuda contextual por país | Admin | Tour steps |
| C6. Tests del formulario por país (mocking country config) | Admin | Tests |

### Fase D — Suscripciones Multi-País (Riesgo ALTO) — ~4 días

| Tarea | Repo | Archivos |
|-------|------|----------|
| D1. Refactorizar PlatformMercadoPagoService (token pool) | API | `src/subscriptions/platform-mercadopago.service.ts` |
| D2. Quitar assertMpSiteIsMLA → validación dinámica | API | Mismo archivo |
| D3. Parametrizar currency_id en createSubscription | API | Mismo archivo |
| D4. Refactorizar createSubscriptionForAccount (multi-moneda) | API | `src/subscriptions/subscriptions.service.ts` |
| D5. Refactorizar checkAndUpdatePrices (repricing multi-moneda) | API | Mismo archivo |
| D6. Actualizar billing para multi-moneda | API | `src/billing/billing.service.ts` |
| D7. Tests: crear suscripción con cada moneda | API | Tests |
| **Configurar tokens MP por país** | **Manual TL** | **MercadoPago + Railway env** |

### Fase E — Seguridad (Riesgo MEDIO) — ~1 día

| Tarea | Repo | Archivos |
|-------|------|----------|
| E1. Implementar CaptchaService (Turnstile) | API | `src/common/captcha.service.ts` |
| E2. Agregar captcha a start-builder | API | `src/onboarding/onboarding.controller.ts` |
| E3. Rate limit por IP (ThrottlerGuard) | API | `src/onboarding/onboarding.controller.ts` |
| E4. Rate limit por email (service-level) | API | `src/onboarding/onboarding.service.ts` |
| E5. Widget Turnstile en frontend | Admin | Componente de inicio |
| E6. Auditar encrypt_mp_token RPC | **Manual TL** | Supabase Dashboard |
| **Crear widget Turnstile en Cloudflare** | **Manual TL** | **Cloudflare Dashboard** |
| **Agregar env vars Turnstile** | **Manual TL** | **Railway + Netlify** |

---

## 11. Acciones Manuales del TL

### 11.1 Antes de empezar (pre-requisitos)

| # | Acción | Dónde | Prioridad |
|---|--------|-------|-----------|
| 1 | **Ejecutar migraciones** ADMIN_080 a ADMIN_084 en Admin DB | Supabase SQL Editor (Admin) | BLOQUEANTE |
| 2 | **Ejecutar migración** BACKEND_048 en Backend DB | Supabase SQL Editor (Backend) | BLOQUEANTE |
| 3 | **Verificar la RPC `encrypt_mp_token`**: revisar que la clave de encriptación sea robusta y esté en env var, no hardcodeada | Supabase Dashboard → SQL → `\df+ encrypt_mp_token` | ALTA |

### 11.2 Para Fase D (suscripciones multi-país)

| # | Acción | Dónde | Prioridad |
|---|--------|-------|-----------|
| 4 | **Registrar NovaVision como marketplace** en MercadoPago para cada país (MLC, MLM, MCO, MLU, MPE) | MercadoPago Developer Portal de cada país | BLOQUEANTE para Fase D |
| 5 | **Obtener access tokens** de plataforma para cada site | MercadoPago Developer Portal | BLOQUEANTE para Fase D |
| 6 | **Agregar env vars** `PLATFORM_MP_ACCESS_TOKEN_{MLC,MLM,MCO,MLU,MPE}` | Railway dashboard | BLOQUEANTE para Fase D |

### 11.3 Para Fase E (seguridad)

| # | Acción | Dónde | Prioridad |
|---|--------|-------|-----------|
| 7 | **Crear cuenta/widget Cloudflare Turnstile** | Cloudflare Dashboard | BLOQUEANTE para E1-E5 |
| 8 | **Agregar env vars Turnstile** (`TURNSTILE_SECRET_KEY`, `VITE_TURNSTILE_SITE_KEY`) | Railway + Netlify | BLOQUEANTE para E1-E5 |

### 11.4 Decisiones de diseño pendientes

| # | Pregunta | Opciones | Impacto |
|---|----------|----------|---------|
| 9 | **¿Cómo se asigna el país a una cuenta nueva?** | A) Geolocalización por IP al crear draft, B) Selector manual en Step1/2, C) Del OAuth de MP | Afecta Step8 y suscripciones |
| 10 | **¿Se habilitan los 6 países de entrada o se hace rollout gradual?** | A) Todos juntos, B) AR+CL primero, luego rest | Afecta tokens MP y testing |
| 11 | **¿Los planes tienen precios locales fijos o siempre USD→FX?** | A) Siempre FX dinámico, B) Precio fijo local (tabla) | Afecta billing y UX |

---

## 12. Testing y QA

### 12.1 Tests unitarios (automáticos)

| Test | Cobertura |
|------|-----------|
| `FiscalIdValidatorService` — CUIT AR válido e inválido | Prefijos 20/30/33, check digit correcto/incorrecto |
| `FiscalIdValidatorService` — RUT CL con K | Body corto/largo, dígito K |
| `FiscalIdValidatorService` — RFC MX | PF (4 letras + 6 dig + 3), PM (3 letras), caracteres especiales Ñ & |
| `FiscalIdValidatorService` — NIT CO | 9 y 10 dígitos, check digit |
| `FiscalIdValidatorService` — RUT UY 12 dígitos | Check digit |
| `FiscalIdValidatorService` — RUC PE con prefijo 10/20 | PF vs PJ, check digit |
| `business-info` endpoint — acepta payload genérico por país | 6 tests (uno por país) |
| `business-info` endpoint — backward compat payload AR | cuit_cuil → fiscal_id |
| `business-info` endpoint — rechaza fiscal_id inválido | Regex + check digit |
| `SubscriptionsService` — crea suscripción con cada moneda | ARS, CLP, MXN, COP, UYU, PEN |
| `PlatformMP` — routing de tokens por site | Token correcto para cada site |
| `CaptchaService` — valida/rechaza token Turnstile | Mock HTTP |
| Rate limit — bloquea después de N intentos por email | count > 3 en última hora |

### 12.2 Tests manuales / E2E

| Scenario | Pasos |
|----------|-------|
| Onboarding AR completo | Crear draft → Step8 con CUIT válido → Verificar persistencia |
| Onboarding CL completo | Crear draft CL → Step8 con RUT + RUN → Verificar regex + check digit CL |
| Onboarding MX completo | Step8 con RFC persona física/moral → Sin check digit |
| Cross-tenant | Cuenta AR no puede ver datos de cuenta CL |
| Repricing multi-moneda | Cron actualiza precios CLP/MXN/COP correctamente |
| Captcha bloqueado | Sin token Turnstile → 400 |
| Rate limit IP | 6to request en 1 min → 429 |
| Rate limit email | 4to draft mismo email → 429 |

---

## 13. Riesgos y Mitigaciones

| Riesgo | Prob | Impacto | Mitigación |
|--------|------|---------|------------|
| Tokens MP de otros países tarda en obtenerse | Alta | Bloquea Fase D | Fase D es independiente; Fases A-C-E se hacen primero |
| Regex de RFC (México) demasiado permisiva | Media | Acepta IDs inválidos | No hay check digit público para RFC; validación server-side mínima es aceptable |
| Dólar blue ≠ dólar oficial para AR | Baja | Precio incorrecto | Ya usa oficial vía dolarapi.com; documentar la decisión |
| Backward compat rompe cuentas AR existentes | Media | Error en cuentas existentes | Doble-write (campo viejo + genérico), migración de datos, tests de regresión |
| Cloudflare Turnstile no disponible/rate limited | Baja | Onboarding bloqueado | Fallback: si no hay env key, skip captcha (solo en dev) |
| Listados de subdivisiones cambian (Chile crea nueva región) | Baja | Opción faltante | Tabla editable por admin; endpoint de admin para agregar |
| Decimales CLP/COP generan centavos | Media | MP rechaza el monto | Redondeo forzado para países con `decimals: 0` |

---

## Anexo A: Listados Completos de Subdivisiones

### Argentina — 24 Provincias
CABA, Buenos Aires, Catamarca, Chaco, Chubut, Córdoba, Corrientes, Entre Ríos, Formosa, Jujuy, La Pampa, La Rioja, Mendoza, Misiones, Neuquén, Río Negro, Salta, San Juan, San Luis, Santa Cruz, Santa Fe, Santiago del Estero, Tierra del Fuego, Tucumán

### Chile — 16 Regiones
Arica y Parinacota, Tarapacá, Antofagasta, Atacama, Coquimbo, Valparaíso, Metropolitana de Santiago, O'Higgins, Maule, Ñuble, Biobío, La Araucanía, Los Ríos, Los Lagos, Aysén, Magallanes

### México — 32 Estados
Aguascalientes, Baja California, Baja California Sur, Campeche, Chiapas, Chihuahua, Coahuila, Colima, Ciudad de México, Durango, Guanajuato, Guerrero, Hidalgo, Jalisco, Estado de México, Michoacán, Morelos, Nayarit, Nuevo León, Oaxaca, Puebla, Querétaro, Quintana Roo, San Luis Potosí, Sinaloa, Sonora, Tabasco, Tamaulipas, Tlaxcala, Veracruz, Yucatán, Zacatecas

### Colombia — 33 Departamentos
Amazonas, Antioquia, Arauca, Atlántico, Bolívar, Boyacá, Caldas, Caquetá, Casanare, Cauca, Cesar, Chocó, Córdoba, Cundinamarca, Bogotá D.C., Guainía, Guaviare, Huila, La Guajira, Magdalena, Meta, Nariño, Norte de Santander, Putumayo, Quindío, Risaralda, San Andrés y Providencia, Santander, Sucre, Tolima, Valle del Cauca, Vaupés, Vichada

### Uruguay — 19 Departamentos
Artigas, Canelones, Cerro Largo, Colonia, Durazno, Flores, Florida, Lavalleja, Maldonado, Montevideo, Paysandú, Río Negro, Rivera, Rocha, Salto, San José, Soriano, Tacuarembó, Treinta y Tres

### Perú — 25 Departamentos
Amazonas, Áncash, Apurímac, Arequipa, Ayacucho, Cajamarca, Cusco, Huancavelica, Huánuco, Ica, Junín, La Libertad, Lambayeque, Lima, Loreto, Madre de Dios, Moquegua, Pasco, Piura, Puno, San Martín, Tacna, Tumbes, Ucayali, Callao

---

## Anexo B: Algoritmos de Dígito Verificador — Implementación Completa

### B.1 CUIT Argentina — Mod 11

```
Entrada: "20-27345678-9" → normalizar a "20273456789"
Pesos:   [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
Cálculo: 2×5 + 0×4 + 2×3 + 7×2 + 3×7 + 4×6 + 5×5 + 6×4 + 7×3 + 8×2 = 166
166 mod 11 = 1 → DV = 11 - 1 = 10 → si 10, DV = 0... (ejemplo ficticio)
Real: el último dígito debe coincidir.
Prefijos válidos: 20,23,24,25,26,27 (persona física) | 30,33,34 (persona jurídica)
```

### B.2 RUT Chile — Mod 11 cíclico con K

```
Entrada: "12.345.678-5" → normalizar a "123456785"
Body: "12345678", DV esperado: "5"
Pesos cíclicos: [2,3,4,5,6,7] desde la derecha
8×2 + 7×3 + 6×4 + 5×5 + 4×6 + 3×7 + 2×2 + 1×3 = 16+21+24+25+24+21+4+3 = 138
138 mod 11 = 6 → DV = 11 - 6 = 5 ✓
Excepción: si resultado = 11 → DV = "0", si = 10 → DV = "K"
```

### B.3 NIT Colombia — Mod 11 con pesos especiales

```
Entrada: "900.123.456-7" → normalizar a "9001234567"
Pesos: [41, 37, 29, 23, 19, 17, 13, 7, 3] (9 dígitos body)
Si tiene 9 dígitos: padear con 0 a la izquierda hasta 9 dígitos body
Suma ponderada mod 11:
  si resto ≤ 1 → DV = 0
  sino → DV = 11 - resto
```

### B.4 RUT Uruguay — Mod 11

```
Entrada: "211234567890" (12 dígitos)
Pesos: [4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] (11 dígitos body)
DV = último dígito
```

### B.5 RUC Perú — Mod 11

```
Entrada: "20123456789" (11 dígitos)
Pesos: [5, 4, 3, 2, 7, 6, 5, 4, 3, 2] (10 dígitos body)
Prefijos: 10 (persona natural), 15/17/20 (persona jurídica)
DV = último dígito
```

### B.6 RFC México

**No tiene algoritmo público de verificación de dígito.** La homoclave (últimos 3 caracteres) es calculada por el SAT con un algoritmo no publicado. Solo se valida formato:
- Persona moral: `^[A-ZÑ&]{3}\d{6}[A-Z0-9]{3}$`
- Persona física: `^[A-ZÑ&]{4}\d{6}[A-Z0-9]{3}$`

---

*Documento escrito para referencia del equipo NovaVision. Debe ser validado por el TL antes de iniciar implementación.*
