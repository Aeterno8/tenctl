#!/bin/bash

# Send email notification using sendmail (HTML format)
# Args: recipient_email, subject, body_html
# Returns: 0 on success, 1 on failure
ptm_send_notification() {
    local recipient=$1
    local subject=$2
    local body_html=$3

    if [ "${EMAIL_NOTIFICATIONS_ENABLED:-false}" != "true" ]; then
        ptm_log DEBUG "Email notifications disabled, skipping"
        return 0
    fi

    if [ -z "$recipient" ] || [ -z "$subject" ] || [ -z "$body_html" ]; then
        ptm_log WARN "ptm_send_notification: missing required parameters"
        return 1
    fi

    ptm_log INFO "Sending notification to $recipient: $subject"

    if command -v sendmail &>/dev/null; then
        {
            echo "From: Tenctl <noreply@$(hostname -f)>"
            echo "To: $recipient"
            echo "Subject: $subject"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/html; charset=utf-8"
            echo ""
            echo "$body_html"
        } | sendmail -t 2>/dev/null
        if [ $? -eq 0 ]; then
            ptm_log INFO "Notification sent to $recipient"
            return 0
        else
            ptm_log WARN "sendmail failed for $recipient"
            return 1
        fi
    else
        ptm_log WARN "sendmail not available, cannot send notification"
        return 1
    fi
}

# HTML email template wrapper - Dark Theme
# Args: title, content_html
ptm_generate_html_email() {
    local title=$1
    local content=$2

    cat <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #0d1117;">
    <table role="presentation" style="width: 100%; border-collapse: collapse;">
        <tr>
            <td style="padding: 40px 20px;">
                <table role="presentation" style="width: 100%; max-width: 580px; margin: 0 auto; background-color: #161b22; border-radius: 8px; border: 1px solid #30363d; overflow: hidden;">
                    <!-- Header -->
                    <tr>
                        <td style="padding: 28px 32px; border-bottom: 1px solid #30363d;">
                            <h1 style="margin: 0; color: #e6edf3; font-size: 18px; font-weight: 600;">Tenctl</h1>
                            <p style="margin: 6px 0 0 0; color: #7d8590; font-size: 14px;">${title}</p>
                        </td>
                    </tr>
                    <!-- Content -->
                    <tr>
                        <td style="padding: 32px;">
                            ${content}
                        </td>
                    </tr>
                    <!-- Footer -->
                    <tr>
                        <td style="padding: 20px 32px; border-top: 1px solid #30363d;">
                            <p style="margin: 0; color: #7d8590; font-size: 12px;">
                                Automatski generisan email
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
EOF
}

# Send tenant welcome email
# Args: tenant_name, username, password, email, vlan_id, subnet, cpu_limit, ram_limit, storage_limit
ptm_send_tenant_welcome_email() {
    local tenant_name=$1
    local username=$2
    local password=$3
    local email=$4
    local vlan_id=$5
    local subnet=$6
    local cpu_limit=$7
    local ram_limit=$8
    local storage_limit=$9

    local subject="Tenant '${tenant_name}' created"

    local content=$(cat <<EOF
<p style="margin: 0 0 24px 0; color: #e6edf3; font-size: 15px; line-height: 1.6;">
    Your tenant <strong style="color: #58a6ff;">${tenant_name}</strong> has been successfully created.
</p>

<!-- Credentials -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px; margin-bottom: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Credentials</p>

    <table style="width: 100%; border-collapse: collapse;">
        <tr>
            <td style="padding: 8px 0; color: #7d8590; font-size: 12px; width: 100px; vertical-align: middle;">Username</td>
            <td style="padding: 8px 0;">
                <table style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; border-collapse: separate;">
                    <tr>
                        <td style="padding: 10px 14px;">
                            <code style="color: #e6edf3; font-family: ui-monospace, monospace; font-size: 14px;">${username}</code>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
        <tr>
            <td style="padding: 8px 0; color: #7d8590; font-size: 12px; vertical-align: middle;">Password</td>
            <td style="padding: 8px 0;">
                <table style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; border-collapse: separate;">
                    <tr>
                        <td style="padding: 10px 14px;">
                            <code style="color: #f0883e; font-family: ui-monospace, monospace; font-size: 14px;">${password}</code>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
        <tr>
            <td style="padding: 8px 0; color: #7d8590; font-size: 12px; vertical-align: middle;">Web GUI</td>
            <td style="padding: 8px 0;">
                <a href="https://$(hostname):8006" style="color: #58a6ff; text-decoration: none; font-size: 14px;">https://$(hostname):8006</a>
            </td>
        </tr>
    </table>
</div>

<!-- Network -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px; margin-bottom: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Network Configuration</p>
    <table style="width: 100%;">
        <tr>
            <td style="color: #7d8590; padding: 6px 0; width: 80px; font-size: 13px;">VLAN</td>
            <td style="color: #e6edf3; font-size: 14px;">${vlan_id}</td>
        </tr>
        <tr>
            <td style="color: #7d8590; padding: 6px 0; font-size: 13px;">Subnet</td>
            <td style="color: #e6edf3; font-size: 14px;">${subnet}</td>
        </tr>
        <tr>
            <td style="color: #7d8590; padding: 6px 0; font-size: 13px;">VNet</td>
            <td><code style="background-color: #1f2428; color: #7ee787; padding: 3px 8px; border-radius: 4px; font-size: 13px;">vn${vlan_id}</code></td>
        </tr>
    </table>
</div>

<!-- Limits -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px; margin-bottom: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Resource Limits</p>
    <table style="width: 100%;">
        <tr>
            <td style="padding: 4px 0;">
                <span style="display: inline-block; background-color: #238636; color: #ffffff; padding: 5px 12px; border-radius: 4px; font-size: 13px; font-weight: 500;">${cpu_limit} CPU</span>
                <span style="display: inline-block; background-color: #1f6feb; color: #ffffff; padding: 5px 12px; border-radius: 4px; font-size: 13px; font-weight: 500; margin-left: 8px;">${ram_limit} MB RAM</span>
                <span style="display: inline-block; background-color: #8957e5; color: #ffffff; padding: 5px 12px; border-radius: 4px; font-size: 13px; font-weight: 500; margin-left: 8px;">${storage_limit} GB</span>
            </td>
        </tr>
    </table>
</div>

<!-- Note -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 16px;">
    <p style="margin: 0; color: #7d8590; font-size: 13px; line-height: 1.5;">
        Use VNet <code style="background-color: #1f2428; color: #7ee787; padding: 2px 6px; border-radius: 4px; font-size: 12px;">vn${vlan_id}</code> for VM network configuration. Resources are automatically validated.
    </p>
</div>
EOF
)

    local html=$(ptm_generate_html_email "New tenant created" "$content")
    ptm_send_notification "$email" "$subject" "$html"
}

# Send tenant removal notification
# Args: tenant_name, email
ptm_send_tenant_removal_email() {
    local tenant_name=$1
    local email=$2

    local subject="Tenant '${tenant_name}' removed"

    local content=$(cat <<EOF
<p style="margin: 0 0 24px 0; color: #e6edf3; font-size: 15px; line-height: 1.6;">
    Tenant <strong style="color: #f85149;">${tenant_name}</strong> has been removed from the system.
</p>

<!-- Deleted Resources -->
<div style="background-color: #0d1117; border: 1px solid #f8514940; border-radius: 6px; padding: 20px; margin-bottom: 20px;">
    <p style="margin: 0 0 16px 0; color: #f85149; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Deleted Resources</p>
    <ul style="margin: 0; padding-left: 20px; color: #e6edf3; font-size: 14px; line-height: 1.8;">
        <li>All VMs and containers</li>
        <li>Network configuration (VNet, VLAN)</li>
        <li>User account and permissions</li>
        <li>Resource pool</li>
    </ul>
</div>

<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 16px;">
    <p style="margin: 0; color: #7d8590; font-size: 13px;">
        If you believe this is an error, contact the administrator.
    </p>
</div>
EOF
)

    local html=$(ptm_generate_html_email "Tenant removed" "$content")
    ptm_send_notification "$email" "$subject" "$html"
}

# Send VM blocked notification
# Args: tenant_name, email, vmid, vmtype, violation_details
ptm_send_vm_blocked_email() {
    local tenant_name=$1
    local email=$2
    local vmid=$3
    local vmtype=$4
    local violation_details=$5

    local subject="Creation of ${vmid} blocked"

    local vm_type_display="VM"
    [ "$vmtype" = "lxc" ] && vm_type_display="Container"

    local content=$(cat <<EOF
<p style="margin: 0 0 24px 0; color: #e6edf3; font-size: 15px; line-height: 1.6;">
    Creation of <strong style="color: #f85149;">${vm_type_display} ${vmid}</strong> has been blocked due to quota exceeded.
</p>

<!-- Error Details -->
<div style="background-color: #0d1117; border: 1px solid #f8514940; border-radius: 6px; padding: 20px; margin-bottom: 20px;">
    <p style="margin: 0 0 16px 0; color: #f85149; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Detalji</p>
    <pre style="margin: 0; color: #e6edf3; font-size: 13px; white-space: pre-wrap; font-family: ui-monospace, 'SF Mono', monospace; line-height: 1.6; background-color: #161b22; padding: 16px; border-radius: 4px; border: 1px solid #30363d;">${violation_details}</pre>
</div>

<!-- Actions -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Possible Actions</p>
    <ul style="margin: 0; padding-left: 20px; color: #e6edf3; font-size: 14px; line-height: 1.8;">
        <li>Reduce resource allocation (CPU, RAM or Storage)</li>
        <li>Delete existing VMs to free up resources</li>
        <li>Contact administrator to increase limits</li>
    </ul>
</div>
EOF
)

    local html=$(ptm_generate_html_email "Creation blocked" "$content")
    ptm_send_notification "$email" "$subject" "$html"
}

# Send VM allowed notification (optional, for audit trail)
# Args: tenant_name, email, vmid, vmtype, cpu, ram, storage
ptm_send_vm_created_email() {
    local tenant_name=$1
    local email=$2
    local vmid=$3
    local vmtype=$4
    local cpu=$5
    local ram=$6
    local storage=$7

    local subject="${vmtype^^} ${vmid} created"

    local vm_type_display="VM"
    [ "$vmtype" = "lxc" ] && vm_type_display="Container"

    local content=$(cat <<EOF
<p style="margin: 0 0 24px 0; color: #e6edf3; font-size: 15px; line-height: 1.6;">
    <strong style="color: #7ee787;">${vm_type_display} ${vmid}</strong> has been successfully created.
</p>

<!-- Resources -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Allocated Resources</p>
    <table style="width: 100%;">
        <tr>
            <td style="color: #7d8590; padding: 6px 0; width: 80px; font-size: 13px;">VMID</td>
            <td style="color: #e6edf3; font-size: 14px; font-weight: 500;">${vmid}</td>
        </tr>
        <tr>
            <td style="color: #7d8590; padding: 6px 0; font-size: 13px;">CPU</td>
            <td style="color: #e6edf3; font-size: 14px;">${cpu} cores</td>
        </tr>
        <tr>
            <td style="color: #7d8590; padding: 6px 0; font-size: 13px;">RAM</td>
            <td style="color: #e6edf3; font-size: 14px;">${ram} MB</td>
        </tr>
        <tr>
            <td style="color: #7d8590; padding: 6px 0; font-size: 13px;">Storage</td>
            <td style="color: #e6edf3; font-size: 14px;">${storage} GB</td>
        </tr>
    </table>
</div>
EOF
)

    local html=$(ptm_generate_html_email "VM created" "$content")
    ptm_send_notification "$email" "$subject" "$html"
}

# Send tenant limits modified notification
# Args: tenant_name, email, old_cpu, old_ram, old_storage, new_cpu, new_ram, new_storage
ptm_send_limits_modified_email() {
    local tenant_name=$1
    local email=$2
    local old_cpu=$3
    local old_ram=$4
    local old_storage=$5
    local new_cpu=$6
    local new_ram=$7
    local new_storage=$8

    local subject="Limits for '${tenant_name}' modified"

    local content=$(cat <<EOF
<p style="margin: 0 0 24px 0; color: #e6edf3; font-size: 15px; line-height: 1.6;">
    Resource limits for tenant <strong style="color: #58a6ff;">${tenant_name}</strong> have been updated.
</p>

<!-- Comparison -->
<div style="background-color: #0d1117; border: 1px solid #30363d; border-radius: 6px; padding: 20px;">
    <p style="margin: 0 0 16px 0; color: #7d8590; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">Changes</p>
    <table style="width: 100%; border-collapse: collapse;">
        <thead>
            <tr>
                <th style="padding: 10px 12px; text-align: left; color: #7d8590; font-size: 12px; font-weight: 500; border-bottom: 1px solid #30363d;">Resurs</th>
                <th style="padding: 10px 12px; text-align: center; color: #7d8590; font-size: 12px; font-weight: 500; border-bottom: 1px solid #30363d;">Pre</th>
                <th style="padding: 10px 12px; text-align: center; color: #7d8590; font-size: 12px; font-weight: 500; border-bottom: 1px solid #30363d;"></th>
                <th style="padding: 10px 12px; text-align: center; color: #7d8590; font-size: 12px; font-weight: 500; border-bottom: 1px solid #30363d;">Posle</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td style="padding: 12px; color: #e6edf3; font-size: 14px;">CPU</td>
                <td style="padding: 12px; text-align: center; color: #7d8590; font-size: 14px;">${old_cpu}</td>
                <td style="padding: 12px; text-align: center; color: #484f58;">→</td>
                <td style="padding: 12px; text-align: center;"><span style="background-color: #238636; color: #fff; padding: 4px 10px; border-radius: 4px; font-size: 13px;">${new_cpu}</span></td>
            </tr>
            <tr>
                <td style="padding: 12px; color: #e6edf3; font-size: 14px;">RAM</td>
                <td style="padding: 12px; text-align: center; color: #7d8590; font-size: 14px;">${old_ram} MB</td>
                <td style="padding: 12px; text-align: center; color: #484f58;">→</td>
                <td style="padding: 12px; text-align: center;"><span style="background-color: #1f6feb; color: #fff; padding: 4px 10px; border-radius: 4px; font-size: 13px;">${new_ram} MB</span></td>
            </tr>
            <tr>
                <td style="padding: 12px; color: #e6edf3; font-size: 14px;">Storage</td>
                <td style="padding: 12px; text-align: center; color: #7d8590; font-size: 14px;">${old_storage} GB</td>
                <td style="padding: 12px; text-align: center; color: #484f58;">→</td>
                <td style="padding: 12px; text-align: center;"><span style="background-color: #8957e5; color: #fff; padding: 4px 10px; border-radius: 4px; font-size: 13px;">${new_storage} GB</span></td>
            </tr>
        </tbody>
    </table>
</div>
EOF
)

    local html=$(ptm_generate_html_email "Limits modified" "$content")
    ptm_send_notification "$email" "$subject" "$html"
}
