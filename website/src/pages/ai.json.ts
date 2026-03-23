import type { APIRoute } from 'astro';

export const prerender = true;

export const GET: APIRoute = () => {
  const data = {
    aiendpoint: '1.0',
    service: {
      name: 'Rerun',
      description:
        'Local, always-on memory for your Mac. Captures everything you work on and makes it searchable. Open source, 100% private.',
      url: 'https://usererun.com',
      category: ['productivity', 'macos', 'open-source'],
    },
    capabilities: [
      {
        id: 'join_waitlist',
        description:
          'Sign up for the Rerun early access waitlist with an email address',
        endpoint: 'https://usererun.com/api/waitlist',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        params: {
          email: {
            type: 'string',
            required: true,
            description: 'Email address to join the waitlist',
          },
        },
        returns:
          'JSON with success status, waitlist position, and referral code',
      },
      {
        id: 'download',
        description:
          'Download the Rerun alpha for macOS (DMG installer)',
        endpoint: 'https://github.com/usererun/rerun/releases/latest/download/Rerun.dmg',
        method: 'GET',
        params: {},
        returns: 'DMG installer file',
      },
    ],
  };

  return new Response(JSON.stringify(data, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  });
};
