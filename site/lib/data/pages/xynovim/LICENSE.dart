import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xynovim/LICENSE',
  lines: [
    heading('# LICENSE'),
    blank,
    ...text('The LICENSE file of xynovim is the unmodified Apache License, Version 2.0, 201 lines, the standard text from apache.org. This page is not about the legal text, which is the same in every project that uses it. It is about the choice: xynovim itself is Apache-2.0, the nine standalone plugins extracted from it are MIT, and on 2026-10-22 the repository briefly switched to MIT and switched back within 23 minutes.'),
    blank,
    kv('role', 'licence of the xynovim configuration itself'),
    kv('language', 'plain text, Apache License 2.0'),
    kv('size', '201 lines, 9 numbered sections and an appendix'),
    kv('plugins', 'the nine xyno-*.nvim repositories each carry an MIT LICENSE, Copyright (c) 2026 Xynorash'),
    kv('badge', 'license-Apache--2.0 in the README'),
    kv('checked by', 'tests/health-bootstrap-ci_spec.lua'),
    blank,
    ...sec('what the file is'),
    ...code('text', r'LICENSE · lines 1-5', r'''
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION'''),
    ...text('The file starts with the standard header, and it was added in the migration commit eabb22a on 2026-09-02, the same commit that turned the repository into a LazyVim-based configuration. Nine sections follow, and the sections that matter to a person who wants to reuse part of the configuration are 2 and 3, the grants of copyright and patent licence.'),
    ...code('text', r'LICENSE · lines 66-71', r'''
   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.'''),
    ...text('Section 4 sets the conditions on redistribution: carry the licence, mark changes, keep notices. Section 5 says contributions are under the same licence unless stated otherwise, section 6 withholds trademark rights, section 7 is the disclaimer of warranty, section 8 the limitation of liability and section 9 covers accepting warranty or additional liability. The file ends with the appendix explaining how to apply the licence to your own work.'),
    ...code('text', r'LICENSE · lines 189-195', r'''
   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0'''),
    ...text('Note what the end of the file is: the appendix, with the placeholder text copyright [yyyy] [name of copyright owner] left as the template has it. This is what you get when you drop the licence text in unchanged. It means the repository has a correct licence text but no line naming the copyright holder inside LICENSE. The README states the licence through a badge and a sentence in the Plugins section, and the author appears in git history, but the copyright line itself was never filled in.'),
    ...sec('why Apache-2.0 for the configuration'),
    ...text('Nothing in the repository states the reason, so this page does not invent one. What the repository does show is how the choice is enforced and communicated. The README badge says Apache-2.0. A spec, tests/health-bootstrap-ci_spec.lua, has a test named LICENSE is the Apache License 2.0 that reads the file and asserts four strings from the standard text. The README sentence in the Plugins section draws the line between the two licences.'),
    ...code('markdown', r'README.md · lines 56-56', r'''
These are the original parts of my config that I extracted into standalone plugins, so anyone can use them without the rest of xynovim. All nine are public, tagged `v0.1.0` with a release, and install with lazy.nvim. The plugins are MIT licensed; xynovim itself stays Apache-2.0. Linux is the platform I test on; each README states what is and is not verified on Windows and macOS. The [plugins page](https://xynorash.github.io/xynovim/plugins/) has the install order, one complete lazy.nvim spec for the Rust toolkit and the questions I expect.'''),
    ...text('That sentence is the whole licensing policy: plugins MIT, xynovim itself Apache-2.0. The nine plugin repositories under ~/projects/xyno-plugins each contain a LICENSE with the MIT text and the line Copyright (c) 2026 Xynorash, which can be verified there, outside this repository.'),
    ...sec('the same-day switch and revert'),
    ...text('The history of this file is short and has one episode that is worth knowing. The LICENSE file has three commits. On 2026-09-02 eabb22a added the Apache text. On 2026-10-22 at 09:48 +0300, commit 536e5cc, titled Voice: review fixes, replaced it with an MIT licence in the same pass that changed the README badge and the site. At 10:11 the same morning, commit 724c508 reverted that change, with a message that says what happened and why.'),
    ...text('The message is the best statement of the policy in the repository: it reverts the licence change of 536e5cc, and says MIT was chosen for the published plugins only. The commit touched twelve files, not only LICENSE: the README, the six guide pages and the home page of the site, the changelog line that had recorded the MIT switch, and the two specs that assert the licence (site_spec.lua and health-bootstrap-ci_spec.lua).'),
    ...bullet('09:48', '536e5cc replaces the Apache text with MIT in LICENSE, in the README badge and on the site. The commit title is about the documentation voice, and the licence was a line inside it.'),
    ...bullet('10:11', '724c508 restores 201 lines of Apache-2.0, and brings the README, the site and the specs back to it.'),
    ...text('The lesson visible in the diff is about consistency. A licence appears in five places in this repository: the file, the README badge, the site pages, the changelog and the specs. Because two specs assert it, the revert could be checked by running them, not by reading.'),
    ...sec('what each licence means in practice'),
    ...bullet('xynovim', 'Apache-2.0: you may use, modify and redistribute the configuration, including commercially; keep the licence and notices, state changes, and the patent grant in section 3 of the file comes with it.'),
    ...bullet('the plugins', 'MIT: each plugin LICENSE reads MIT License with the line Copyright (c) 2026 Xynorash. Each plugin repository is its own work with its own LICENSE, which is why they can be used without the rest of xynovim.'),
    ...bullet('third-party code', 'xynovim installs its plugins through lazy.nvim from their own repositories, pinned by lazy-lock.json, so their licences stay with them. The Island Dark palette is generated from the author’s own scheme export, and the README acknowledgement says it is derived from JetBrains’ Islands Dark scheme and that the project is not affiliated with JetBrains. The converter does not ship the export itself.'),
    ...sec('how it is tested'),
    ...text('One spec checks the file and it is deliberately light: tests/health-bootstrap-ci_spec.lua, in its describe block for .gitignore and LICENSE, reads LICENSE and asserts the title line, the version string, the apache.org URL and the terms heading. It does not check the appendix or the text of any section, so an accidental edit to the body would pass. tests/site_spec.lua checks the licence name on the website.'),
    ...code('lua', r'tests/health-bootstrap-ci_spec.lua · lines 899-904', r'''
  it("LICENSE is the Apache License 2.0", function()
    local l = read("LICENSE")
    H.has(l, "Apache License\n")
    H.has(l, "Version 2.0, January 2004")
    H.has(l, "http://www.apache.org/licenses/")
    H.has(l, "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION")'''),
    ...sec('design notes'),
    ...bullet('Unmodified text', 'the file is the standard Apache text; the only unfilled part is the appendix placeholder.'),
    ...bullet('Two licences by role', 'the repository states which licence goes where but not why; the commit message says only that MIT was chosen for the published plugins.'),
    ...bullet('Policy in one sentence', 'the README says plugins MIT, xynovim Apache-2.0, and a commit message says the same.'),
    ...sec('history'),
    ...bullet('2026-09-02', 'eabb22a adds the Apache-2.0 LICENSE.'),
    ...bullet('2026-10-22 09:48', '536e5cc switches to MIT.'),
    ...bullet('2026-10-22 10:11', '724c508 reverts, keeping MIT for the plugins only.'),
    blank,
  ],
);
