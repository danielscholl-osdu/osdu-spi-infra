// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
	site: 'https://danielscholl-osdu.github.io',
	base: '/osdu-spi-infra',
	integrations: [
		starlight({
			title: 'OSDU SPI Infrastructure',
			description: 'Infrastructure as Code for deploying the OSDU Azure SPI on AKS Automatic',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/danielscholl-osdu/osdu-spi-infra' }],
			editLink: {
				baseUrl: 'https://github.com/danielscholl-osdu/osdu-spi-infra/edit/main/docs/',
			},
			sidebar: [
				{
					label: 'Getting Started',
					items: [
						{ label: 'Introduction', slug: 'getting-started/introduction' },
						{ label: 'Prerequisites', slug: 'getting-started/prerequisites' },
						{ label: 'Quick Start', slug: 'getting-started/quick-start' },
						{ label: 'Configuration', slug: 'getting-started/configuration' },
					],
				},
				{
					label: 'Design',
					items: [
						{ label: 'Overview', slug: 'design/overview' },
						{ label: 'Deployment Model', slug: 'design/deployment-model' },
						{ label: 'Infrastructure', slug: 'design/infrastructure' },
						{ label: 'Platform Services', slug: 'design/platform-services' },
						{ label: 'Service Architecture', slug: 'design/service-architecture' },
						{ label: 'Traffic & Routing', slug: 'design/traffic-routing' },
						{ label: 'Security', slug: 'design/security' },
					],
				},
				{
					label: 'Decisions',
					items: [
						{ label: 'Overview', slug: 'decisions/overview' },
						{ label: 'ADR-0001: Three-Layer Model', slug: 'decisions/0001-three-layer-deployment-model' },
						{ label: 'ADR-0002: Hybrid PaaS', slug: 'decisions/0002-azure-paas-with-in-cluster-middleware' },
						{ label: 'ADR-0003: Local Helm Chart', slug: 'decisions/0003-local-helm-chart-for-safeguards-compliance' },
						{ label: 'ADR-0004: Istio CNI Chaining', slug: 'decisions/0004-istio-cni-chaining-for-sidecar-injection' },
						{ label: 'ADR-0005: Health Probes', slug: 'decisions/0005-per-service-health-probe-configuration' },
					],
				},
				{
					label: 'Operations',
					items: [
						{ label: 'Monitoring', slug: 'operations/monitoring' },
						{ label: 'Troubleshooting', slug: 'operations/troubleshooting' },
					],
				},
			],
		}),
	],
});
