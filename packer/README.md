## Packer Templates for Centos8 with ZFS Root

This repository contains [Packer][packerio] templates for building Amazon Machine Images for Ubuntu with a ZFS root
filesystem. Currently the following distributions are supported:

- Centos 8 with AWS-Optimized Kernel

The template is easily modified for Debian and other Ubuntu distributions.

You can read about how this template works on the [jen20.dev][oe] blog. Some relevant posts:

## Credits

Thanks to:
- [Alan Ivey][alanivey] for [this post][alaniveypost] about the nvme0n1 and zfs
- [Scott Emmons][scotte] for [this post][scottepost] about the steps required to build Linux AMIs with a ZFS root filesystem.
- [Sean Chittenden][seanc] for reviewing the template and blog post prior to publication.
- [Zachary Schneider][zachs] for reviewing the template and blog post prior to publication.

[oe]: https://operator-error.com
[oepost1]: https://jen20.dev/post/building-zfs-root-ubuntu-amis-with-packer/ 
[oepost2]: https://jen20.dev/post/ubuntu-18.04-with-root-zfs-on-aws/
[oepost3]: https://jen20.dev/post/ubuntu-20.04-with-root-zfs-in-aws/
[scotte]: https://www.scotte.org
[scottepost]: https://www.scotte.org/2016/12/ZFS-root-filesystem-on-AWS
[seanc]: https://twitter.com/seanchittenden
[zachs]: https://twitter.com/sigil66
[packerio]: https://packer.io
[packerrepo]: https://github.com/hashicorp/packer
[alanivey]: https://alan.ivey.dev/
[alaniveypost]: https://alan.ivey.dev/posts/2020/creating-an-ami-for-arm/
