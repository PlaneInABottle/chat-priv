FROM andrius/asterisk:latest

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5060/udp 5061/udp 10000-10100/udp

ENTRYPOINT ["/entrypoint.sh"]
